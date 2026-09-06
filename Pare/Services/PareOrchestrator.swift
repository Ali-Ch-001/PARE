// PareOrchestrator.swift - End-to-End Reactive Pipeline Orchestrator
import Foundation
import SwiftUI
import Photos

public struct CuratedClusterCard: Identifiable {
    public let id: String
    public let heroIdentifier: String
    public let redundantIdentifiers: [String]
    public let reclaimableBytes: UInt64
    public let title: String
    public let candidateCount: Int
    public let heroQuality: Float

    public init(
        id: String,
        heroIdentifier: String,
        redundantIdentifiers: [String],
        reclaimableBytes: UInt64,
        title: String,
        candidateCount: Int,
        heroQuality: Float
    ) {
        self.id = id
        self.heroIdentifier = heroIdentifier
        self.redundantIdentifiers = redundantIdentifiers
        self.reclaimableBytes = reclaimableBytes
        self.title = title
        self.candidateCount = candidateCount
        self.heroQuality = heroQuality
    }
}

@MainActor
@Observable
public final class PareOrchestrator {
    public static let shared = PareOrchestrator()

    // Observable UI Pipeline States
    public var isProcessing: Bool = false
    public var currentStageName: String = "IDLE"
    public var processedCount: Int = 0
    public var totalCount: Int = 0
    public var currentStageIndex: Int = 0 // 0: Heuristics, 1: Popcount, 2: CELF

    // Curated Deck for ReviewDeckView
    public var activeClusters: [CuratedClusterCard] = []
    public var currentClusterIndex: Int = 0
    public var totalReclaimedLifetimeBytes: Int64 = 0

    public var isPermissionDenied: Bool = false
    public var iCloudSkippedCount: Int = 0

    /// True amount of storage the user can reclaim with 1 tap right now
    public var effectiveAutoCleanReclaimableBytes: UInt64 {
        return remainingReclaimableBytes
    }

    /// Unified method to record storage reclaims
    public func recordReclaimedBytes(_ bytes: Int64, count: Int = 1) {
        PareStorage.shared.addReclaimedBytes(bytes)
        PareStorage.shared.addCleanedItemsCount(count)
        self.totalReclaimedLifetimeBytes += bytes
    }

    private init() {
        self.totalReclaimedLifetimeBytes = PareStorage.shared.getTotalReclaimedBytes()
    }

    /// Fast single-cycle hardware popcount Hamming distance between two 128-bit hashes
    nonisolated public static func hammingDistance(_ a: [UInt32], _ b: [UInt32]) -> UInt32 {
        guard a.count >= 4 && b.count >= 4 else { return 128 }
        return UInt32((a[0] ^ b[0]).nonzeroBitCount +
                      (a[1] ^ b[1]).nonzeroBitCount +
                      (a[2] ^ b[2]).nonzeroBitCount +
                      (a[3] ^ b[3]).nonzeroBitCount)
    }

    /// Primary execution flow triggered by "Start Deep Clean" button (Full-Library Incremental GPU Pipeline)
    public func startDeepCleanPipeline(limit: Int = Int.max) async {
        guard !isProcessing else { return }
        self.isProcessing = true
        self.processedCount = 0
        self.totalCount = 100
        self.activeClusters.removeAll()
        self.currentClusterIndex = 0

        // -------------------------------------------------------------
        // PHASE 1: NATIVE HEURISTICS & PERSISTENT HASH HYDRATION
        // -------------------------------------------------------------
        self.currentStageName = "Reading your photos…"
        self.currentStageIndex = 0

        let auth = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        guard auth == .authorized || auth == .limited else {
            self.isProcessing = false
            self.isPermissionDenied = true
            self.currentStageName = "Photo access needed"
            return
        }
        self.isPermissionDenied = false

        let totalPhotos = await ParePhotoScanner.shared.fetchLibraryPhotoCount()
        self.totalCount = max(totalPhotos, 1)

        let candidates = await ParePhotoScanner.shared.scanIncrementalCandidates(limit: limit) { [weak self] done, total in
            if done % 20 == 0 || done == total {
                Task { @MainActor in
                    self?.processedCount = done
                    self?.totalCount = max(total, 1)
                }
            }
        }
        self.totalCount = max(candidates.count, 1)
        self.processedCount = candidates.count

        await executeCurationPipeline(with: candidates)
    }

    /// Dedicated per-album curation flow: analyzes and cleans photos strictly within a specific album
    public func startAlbumCurationPipeline(for collection: PHAssetCollection) async {
        guard !isProcessing else { return }
        self.isProcessing = true
        self.processedCount = 0
        self.activeClusters.removeAll()
        self.currentClusterIndex = 0

        let albumTitle = collection.localizedTitle ?? "Album"
        self.currentStageName = "Reading \(albumTitle)…"
        self.currentStageIndex = 0

        let candidates = await ParePhotoScanner.shared.scanAlbumCandidates(collection: collection) { [weak self] done, total in
            if done % 10 == 0 || done == total {
                Task { @MainActor in
                    self?.processedCount = done
                    self?.totalCount = max(total, 1)
                }
            }
        }
        self.totalCount = max(candidates.count, 1)
        self.processedCount = candidates.count

        guard candidates.count >= 2 else {
            self.isProcessing = false
            self.currentStageName = "Done"
            return
        }

        await executeCurationPipeline(with: candidates)
    }

    /// Shared GPU Multi-Table LSH + Bounded Hamming + CELF submodular curation engine
    private func executeCurationPipeline(with candidates: [ScannedCandidate]) async {
        // -------------------------------------------------------------
        // PHASE 2: MULTI-TABLE GPU LSH & BOUNDED HAMMING DISTANCE
        // -------------------------------------------------------------
        self.currentStageName = "Finding duplicates…"
        self.currentStageIndex = 1

        self.iCloudSkippedCount = candidates.filter { !$0.hasValidVisualHash }.count

        // Only candidates with valid visual feature prints participate in duplicate clustering
        let visualCandidates = candidates.filter { $0.hasValidVisualHash }
        guard visualCandidates.count >= 2 else {
            self.processedCount = self.totalCount
            self.activeClusters = []
            self.isProcessing = false
            self.currentStageName = "Done"
            return
        }

        let userRuthlessness = UserDefaults.standard.object(forKey: "pare_curation_ruthlessness") as? Double ?? 0.50
        // Monotonic Ruthlessness calibration:
        // Gentle (< 0.35): maxDist = 10 bits, keeps ~50% of cluster as keepers (deletes fewest)
        // Balanced (0.35 ..< 0.70): maxDist = 15 bits, keeps ~25% as heroes
        // Thorough (>= 0.70): maxDist = 20 bits, keeps strictly 1 hero (deletes most)
        let maxPairwiseDistance: UInt32
        let effectiveMu: Float
        if userRuthlessness < 0.35 {
            maxPairwiseDistance = 10
            effectiveMu = 0.20
        } else if userRuthlessness < 0.70 {
            maxPairwiseDistance = 15
            effectiveMu = 0.50
        } else {
            maxPairwiseDistance = 20
            effectiveMu = 0.85
        }

        // Offload heavy graph clustering & CELF optimization to background detached task
        let curatedCards: [CuratedClusterCard] = await Task.detached(priority: .userInitiated) {
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

            // 1. Dispatch zero-allocation GPU Multi-Table LSH (L=4) + Bounded Triangular Hamming Distance
            let gpuClusterIndices = PareEngineBridge.sharedEngine().findDuplicateClusters(
                withPackedHashes: rawHashData,
                count: UInt(visualCandidates.count),
                maxDistance: maxPairwiseDistance
            )

            var clusteredIDs = Set<String>()
            var candidateClusters: [[ScannedCandidate]] = []

            // A. Extract verified clusters from Metal GPU pipeline
            for idxArray in gpuClusterIndices {
                let cluster = idxArray.compactMap { idx -> ScannedCandidate? in
                    let i = idx.intValue
                    return i < visualCandidates.count ? visualCandidates[i] : nil
                }
                if cluster.count >= 2 {
                    for c in cluster { clusteredIDs.insert(c.localIdentifier) }
                    candidateClusters.append(cluster)
                }
            }

            // B. Temporal Burst / Rapid-Snap Clusters (consecutive photos within <= 60s with visual similarity)
            var i = 0
            while i < visualCandidates.count {
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
                    candidateClusters.append(burstGroup)
                    i = j
                } else {
                    i += 1
                }
            }

            // -------------------------------------------------------------
            // PHASE 3: WINDOWED NEMHAUSER CELF SUBMODULAR SOLVER
            // -------------------------------------------------------------
            var cards: [CuratedClusterCard] = []

            for (wIdx, chunk) in candidateClusters.enumerated() {
                guard chunk.count >= 2 else { continue }

                var hashes: [[NSNumber]] = []
                var qualities: [NSNumber] = []
                var fileBytes: [NSNumber] = []

                for item in chunk {
                    hashes.append(item.hashWords.map { NSNumber(value: $0) })
                    qualities.append(NSNumber(value: item.qualityScore))
                    fileBytes.append(NSNumber(value: item.fileBytes))
                }

                let targetK: UInt
                if userRuthlessness < 0.35 {
                    targetK = UInt(max(1, (chunk.count + 1) / 2)) // Gentle: Keep ~50% of cluster
                } else if userRuthlessness < 0.70 {
                    targetK = (chunk.count <= 4) ? 1 : UInt(max(1, chunk.count / 4)) // Balanced
                } else {
                    targetK = 1 // Thorough: Keep strictly 1 hero
                }

                let result = PareEngineBridge.sharedEngine().curateWindow(
                    withHashes: hashes,
                    qualityScores: qualities,
                    fileBytes: fileBytes,
                    targetK: targetK,
                    ruthlessnessMu: effectiveMu,
                    qualityLambda: 0.35
                )

                if !result.redundantIndices.isEmpty && !result.heroIndices.isEmpty {
                    let heroCandidate = chunk[Int(result.heroIndex)]
                    let redundantIds = result.redundantIndices.map { chunk[$0.intValue].localIdentifier }

                    let title: String
                    if let date = heroCandidate.creationDate {
                        let formatter = DateFormatter()
                        formatter.dateFormat = "MMM d • h:mm a"
                        title = "EVENT CAPTURE • \(formatter.string(from: date).uppercased())"
                    } else {
                        title = "EVENT CLUSTER #\(wIdx + 1)"
                    }

                    let card = CuratedClusterCard(
                        id: UUID().uuidString,
                        heroIdentifier: heroCandidate.localIdentifier,
                        redundantIdentifiers: redundantIds,
                        reclaimableBytes: result.reclaimableBytes,
                        title: title,
                        candidateCount: chunk.count,
                        heroQuality: heroCandidate.qualityScore
                    )
                    cards.append(card)

                    // Persist cluster to SQLite
                    _ = PareStorage.shared.saveCluster(
                        heroIdentifier: heroCandidate.localIdentifier,
                        memberIdentifiers: chunk.map { $0.localIdentifier },
                        reclaimableBytes: result.reclaimableBytes,
                        coverageScore: result.coverageScore
                    )
                }
            }

            return cards
        }.value

        // Clear checkpoint upon successful completion of the full library pass
        PareStorage.shared.clearCheckpoint()

        self.processedCount = self.totalCount
        self.activeClusters = curatedCards
        self.isProcessing = false
        self.currentStageName = "Done"
    }

    /// Executes soft-deletion of redundant photos in the active cluster card
    public func trashCurrentCluster() async {
        guard currentClusterIndex < activeClusters.count else { return }
        let currentCard = activeClusters[currentClusterIndex]

        do {
            let deletedCount = try await PareTrashManager.shared.softDeleteAssets(
                localIdentifiers: currentCard.redundantIdentifiers
            )
            if deletedCount > 0 {
                let reclaimed = Int64(currentCard.reclaimableBytes)
                self.recordReclaimedBytes(reclaimed, count: deletedCount)
            }
        } catch {
            print("[PareOrchestrator] Soft delete failed: \(error.localizedDescription)")
        }

        self.advanceCluster()
    }

    /// Automatically batches and soft-deletes redundant photos across all remaining clusters in 1 tap
    @discardableResult
    public func trashAllRemainingClusters() async -> (deletedCount: Int, reclaimedBytes: Int64) {
        guard currentClusterIndex < activeClusters.count else { return (0, 0) }

        var allRedundantIds: [String] = []
        var totalBytesToReclaim: Int64 = 0

        for i in currentClusterIndex..<activeClusters.count {
            let card = activeClusters[i]
            allRedundantIds.append(contentsOf: card.redundantIdentifiers)
            totalBytesToReclaim += Int64(card.reclaimableBytes)
        }

        guard !allRedundantIds.isEmpty else {
            return (0, 0)
        }

        do {
            let deletedCount = try await PareTrashManager.shared.softDeleteAssets(
                localIdentifiers: allRedundantIds
            )
            if deletedCount > 0 {
                self.recordReclaimedBytes(totalBytesToReclaim, count: deletedCount)
                
                // Advance all clusters to complete
                self.currentClusterIndex = activeClusters.count
                return (deletedCount, totalBytesToReclaim)
            }
        } catch {
            print("[PareOrchestrator] Batch soft delete failed: \(error.localizedDescription)")
        }

        return (0, 0)
    }

    /// Computes total reclaimable bytes across all remaining active clusters
    public var remainingReclaimableBytes: UInt64 {
        guard currentClusterIndex < activeClusters.count else { return 0 }
        var sum: UInt64 = 0
        for i in currentClusterIndex..<activeClusters.count {
            sum += activeClusters[i].reclaimableBytes
        }
        return sum
    }

    /// Total number of redundant candidate photos across all remaining active clusters
    public var remainingRedundantPhotoCount: Int {
        guard currentClusterIndex < activeClusters.count else { return 0 }
        var sum = 0
        for i in currentClusterIndex..<activeClusters.count {
            sum += activeClusters[i].redundantIdentifiers.count
        }
        return sum
    }

    /// Skips the current cluster without deleting
    public func ignoreCurrentCluster() {
        self.advanceCluster()
    }

    public func advanceCluster() {
        if currentClusterIndex < activeClusters.count {
            currentClusterIndex += 1
        }
    }
}
