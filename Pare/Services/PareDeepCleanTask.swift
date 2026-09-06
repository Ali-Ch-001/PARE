// PareDeepCleanTask.swift - Autonomous Background Deep Clean Task
import Foundation
import BackgroundTasks
import Photos
import UserNotifications

public final class PareDeepCleanTask: @unchecked Sendable {
    public static let shared = PareDeepCleanTask()
    public static let taskIdentifier = "com.pare.engine.deepclean"

    private let stateLock = NSLock()
    private var _isCancelled: Bool = false
    private var _lastRecoveredBytes: Int64 = 0

    private init() {}

    private var isCancelled: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return _isCancelled
    }

    private func setCancelled(_ val: Bool) {
        stateLock.lock()
        defer { stateLock.unlock() }
        _isCancelled = val
    }

    private var lastRecoveredBytes: Int64 {
        stateLock.lock()
        defer { stateLock.unlock() }
        return _lastRecoveredBytes
    }

    private func setLastRecoveredBytes(_ bytes: Int64) {
        stateLock.lock()
        defer { stateLock.unlock() }
        _lastRecoveredBytes = bytes
    }

    /// Registers the BGProcessingTask with the system scheduler.
    /// Must be invoked in application didFinishLaunchingWithOptions before launch completes.
    public func register() {
        #if os(iOS)
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.taskIdentifier, using: nil) { task in
            guard let processingTask = task as? BGProcessingTask else { return }
            self.handleDeepClean(task: processingTask)
        }
        #endif
    }

    /// Requests system notification authorization for morning curation alerts
    @discardableResult
    public func requestNotificationPermission() async -> Bool {
        let center = UNUserNotificationCenter.current()
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            return granted
        } catch {
            print("[PareDeepCleanTask] Notification authorization error: \(error.localizedDescription)")
            return false
        }
    }

    /// Submits a request to the system to wake the app overnight when the phone is charging.
    public func scheduleNext() {
        #if os(iOS)
        let request = BGProcessingTaskRequest(identifier: Self.taskIdentifier)
        request.requiresExternalPower = true          // Nightly constraint: only runs when plugged in
        request.requiresNetworkConnectivity = false   // 100% on-device local execution
        request.earliestBeginDate = Date(timeIntervalSinceNow: 4 * 3600) // Minimum 4 hour delay (e.g. 3:00 AM)

        do {
            try BGTaskScheduler.shared.submit(request)
            print("[PareDeepCleanTask] Successfully scheduled overnight background task.")
        } catch {
            print("[PareDeepCleanTask] Failed to schedule BGProcessingTask: \(error.localizedDescription)")
        }
        #endif
    }

    #if os(iOS)
    /// Background task handler invoked by iOS kernel when hardware conditions are met.
    private func handleDeepClean(task: BGProcessingTask) {
        self.setCancelled(false)

        // Expiration Handler: OS gives 2-5 seconds warning before terminating
        task.expirationHandler = {
            self.setCancelled(true)
            print("[PareDeepCleanTask] Expiration warning received from iOS kernel. Flushing checkpoints.")
        }

        Task.detached(priority: .background) {
            let success = await self.executeOvernightPipeline()
            if success && !self.isCancelled {
                await self.postCompletionNotification()
            }
            self.scheduleNext() // Reschedule for next sleep cycle
            task.setTaskCompleted(success: success && !self.isCancelled)
        }
    }
    #endif

    private func executeOvernightPipeline() async -> Bool {
        // Step 1: Query unindexed photos via PhotoKit
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else {
            return false
        }

        // Step 2: Enumerate candidate assets via incremental scan (Zero-cost SQLite hydration + new photos)
        let candidates = await ParePhotoScanner.shared.scanIncrementalCandidates(limit: Int.max)
        guard !candidates.isEmpty, !self.isCancelled else {
            return true
        }

        // Only assets with valid visual hashes participate in duplicate clustering
        let visualCandidates = candidates.filter { $0.hasValidVisualHash }
        guard visualCandidates.count >= 2 else {
            return true
        }

        // Zero-Allocation Flat Raw Bytes Buffer (Bypasses 200,000 NSNumber allocations at 50K scale)
        var rawHashData = Data(count: visualCandidates.count * 16)
        rawHashData.withUnsafeMutableBytes { (rawBuffer: UnsafeMutableRawBufferPointer) in
            guard let basePtr = rawBuffer.baseAddress?.assumingMemoryBound(to: UInt32.self) else { return }
            var offset = 0
            for cand in visualCandidates {
                if cand.hashWords.count >= 4 {
                    basePtr[offset] = cand.hashWords[0]
                    basePtr[offset + 1] = cand.hashWords[1]
                    basePtr[offset + 2] = cand.hashWords[2]
                    basePtr[offset + 3] = cand.hashWords[3]
                }
                offset += 4
            }
        }

        let userRuthlessness = UserDefaults.standard.double(forKey: "pare_curation_ruthlessness")
        let effectiveMu = userRuthlessness > 0.0 ? Float(userRuthlessness) : 0.50
        let maxPairwiseDistance: UInt32 = UInt32(12.0 + Double(effectiveMu) * 10.0)

        // Step 3: Zero-allocation GPU Multi-Table LSH (L=4) + Bounded Triangular Hamming Distance
        let gpuClusterIndices = PareEngineBridge.sharedEngine().findDuplicateClusters(
            withPackedHashes: rawHashData,
            count: UInt(visualCandidates.count),
            maxDistance: maxPairwiseDistance
        )

        var clusteredIDs = Set<String>()
        var verifiedClusters: [[ScannedCandidate]] = []

        for idxArray in gpuClusterIndices {
            let cluster = idxArray.compactMap { idx -> ScannedCandidate? in
                let i = idx.intValue
                return i < visualCandidates.count ? visualCandidates[i] : nil
            }
            if cluster.count >= 2 {
                for c in cluster { clusteredIDs.insert(c.localIdentifier) }
                verifiedClusters.append(cluster)
            }
        }

        // B. Temporal Burst / Rapid-Snap Clusters
        var i = 0
        while i < visualCandidates.count {
            guard !self.isCancelled else { return false }
            let current = visualCandidates[i]
            if clusteredIDs.contains(current.localIdentifier) {
                i += 1
                continue
            }

            var burstGroup: [ScannedCandidate] = [current]
            var j = i + 1

            while j < visualCandidates.count && j < i + 25 {
                let next = visualCandidates[j]
                if clusteredIDs.contains(next.localIdentifier) {
                    j += 1
                    continue
                }

                let isSameBurst = (current.isBurst && next.isBurst)
                var isTemporallyClose = false
                if let d1 = current.creationDate, let d2 = next.creationDate {
                    if abs(d1.timeIntervalSince(d2)) <= 60.0 {
                        isTemporallyClose = true
                    }
                }

                if isSameBurst || isTemporallyClose {
                    let dist = PareOrchestrator.hammingDistance(current.hashWords, next.hashWords)
                    if dist <= maxPairwiseDistance {
                        burstGroup.append(next)
                    }
                } else {
                    break
                }
                j += 1
            }

            if burstGroup.count >= 2 {
                for b in burstGroup { clusteredIDs.insert(b.localIdentifier) }
                verifiedClusters.append(burstGroup)
                i = j
            } else {
                i += 1
            }
        }

        // Step 4: Curate each verified cluster individually
        var totalReclaimed: Int64 = 0

        for (wIdx, chunk) in verifiedClusters.enumerated() {
            guard !self.isCancelled else { return false }
            guard chunk.count >= 2 else { continue }

            var hashes: [[NSNumber]] = []
            var qualities: [NSNumber] = []
            var fileBytes: [NSNumber] = []

            for item in chunk {
                hashes.append(item.hashWords.map { NSNumber(value: $0) })
                qualities.append(NSNumber(value: item.qualityScore))
                fileBytes.append(NSNumber(value: item.fileBytes))
            }

            let targetK: UInt = (chunk.count <= 4) ? 1 : UInt(max(1, chunk.count / 4))

            let result = PareEngineBridge.sharedEngine().curateWindow(
                withHashes: hashes,
                qualityScores: qualities,
                fileBytes: fileBytes,
                targetK: targetK,
                ruthlessnessMu: effectiveMu,
                qualityLambda: 0.35
            )

            guard !result.redundantIndices.isEmpty && !result.heroIndices.isEmpty else {
                continue
            }

            let heroCandidate = chunk[Int(result.heroIndex)]

            // Persist cluster staged for morning 1-tap review
            _ = PareStorage.shared.saveCluster(
                heroIdentifier: heroCandidate.localIdentifier,
                memberIdentifiers: chunk.map { $0.localIdentifier },
                reclaimableBytes: result.reclaimableBytes,
                coverageScore: result.coverageScore
            )

            totalReclaimed += Int64(result.reclaimableBytes)

            // Transactional checkpoint after each cluster
            PareStorage.shared.saveCheckpoint(
                stage: "OVERNIGHT_DEEP_CLEAN",
                lastAssetId: chunk.last?.localIdentifier,
                totalScanned: (wIdx + 1) * 20
            )
        }

        self.setLastRecoveredBytes(totalReclaimed)
        PareStorage.shared.clearCheckpoint()
        return true
    }

    private func postCompletionNotification() async {
        let bytes = self.lastRecoveredBytes
        guard bytes > 50 * 1024 * 1024 else { return } // Only notify if > 50 MB staged

        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized else { return }

        let content = UNMutableNotificationContent()
        let gb = Double(bytes) / 1_073_741_824.0

        content.title = "Pare Overnight Curation Complete"
        content.body = String(format: "Staged %.1f GB of duplicate clutter while you slept. Tap to review and reclaim in 1 tap.", gb)
        content.sound = .default

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        try? await center.add(request)
    }

    public func getLastRecoveredBytes() -> Int64 {
        return self.lastRecoveredBytes
    }
}
