// ParePhotoScanner.swift - Production Vision Batch Scanner & Stage 1 Heuristics
import Foundation
import Photos
import Vision
import Accelerate

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
public typealias UIImage = NSImage
extension NSImage {
    public var cgImage: CGImage? {
        var rect = CGRect(origin: .zero, size: self.size)
        return self.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }
}
#endif

public struct ScannedCandidate {
    public let localIdentifier: String
    public let hashWords: [UInt32]
    public let qualityScore: Float
    public let fileBytes: UInt64
    public let creationDate: Date?
    public let isScreenshot: Bool
    public let isBurst: Bool
    public let hasValidVisualHash: Bool

    public init(
        localIdentifier: String,
        hashWords: [UInt32],
        qualityScore: Float,
        fileBytes: UInt64,
        creationDate: Date?,
        isScreenshot: Bool,
        isBurst: Bool,
        hasValidVisualHash: Bool = true
    ) {
        self.localIdentifier = localIdentifier
        self.hashWords = hashWords
        self.qualityScore = qualityScore
        self.fileBytes = fileBytes
        self.creationDate = creationDate
        self.isScreenshot = isScreenshot
        self.isBurst = isBurst
        self.hasValidVisualHash = hasValidVisualHash
    }
}

public final class ParePhotoScanner: @unchecked Sendable {
    public static let shared = ParePhotoScanner()
    private let projectionMatrix: [Float]
    private let scannerQueue = DispatchQueue(label: "com.pare.scanner.vision", qos: .userInitiated, attributes: .concurrent)

    private init() {
        self.projectionMatrix = SimHashProjector.loadOrCreateProjectionMatrix()
    }

    /// Scans photo assets asynchronously, running Apple Vision feature extraction in concurrent batches
    public func scanCandidatesForCuration(limit: Int = Int.max) async -> [ScannedCandidate] {
        return await scanIncrementalCandidates(limit: limit, progressHandler: nil)
    }

    /// Scalable incremental scanner: loads existing hashes from SQLite WAL in O(1) time
    /// and extracts Vision feature prints ONLY for newly added photos.
    public func scanIncrementalCandidates(
        limit: Int = Int.max,
        progressHandler: ((Int, Int) -> Void)? = nil
    ) async -> [ScannedCandidate] {
        let known = PareStorage.shared.knownAssetIdentifiers()

        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        if limit != Int.max {
            fetchOptions.fetchLimit = limit
        }
        fetchOptions.includeHiddenAssets = false

        let assets = PHAsset.fetchAssets(with: fetchOptions)
        let totalCount = assets.count
        guard totalCount > 0 else {
            return []
        }

        var newAssetsToProcess: [PHAsset] = []
        newAssetsToProcess.reserveCapacity(min(totalCount, 5000))

        assets.enumerateObjects { asset, _, _ in
            if asset.isFavorite { return }
            if PareTrashManager.shared.isAssetProtected(asset.localIdentifier) { return }
            if !known.contains(asset.localIdentifier) {
                newAssetsToProcess.append(asset)
            }
        }

        // If no new photos need hashing, hydrate directly from SQLite
        if newAssetsToProcess.isEmpty {
            let persisted = PareStorage.shared.loadPersistedCandidates()
            progressHandler?(persisted.count, persisted.count)
            return persisted
        }

        // Hash newly discovered assets in parallel
        let newlyHashed = await hashAssets(newAssetsToProcess, progressHandler: progressHandler)

        // Immediately persist newly hashed candidates before clustering so work is never lost
        PareStorage.shared.upsertAssetHashes(newlyHashed)

        // Return unified library
        return PareStorage.shared.loadPersistedCandidates()
    }

    /// Internal high-throughput hashing engine for unindexed assets (Guaranteed zero-deadlock serial queue)
    private func hashAssets(_ assets: [PHAsset], progressHandler: ((Int, Int) -> Void)?) async -> [ScannedCandidate] {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let manager = PHImageManager.default()
                let requestOptions = PHImageRequestOptions()
                requestOptions.isSynchronous = true
                requestOptions.isNetworkAccessAllowed = false // Local cached 256px thumbnails only
                requestOptions.deliveryMode = .fastFormat
                requestOptions.resizeMode = .fast

                let totalCount = assets.count
                var candidates: [ScannedCandidate] = []
                candidates.reserveCapacity(totalCount)

                for (idx, asset) in assets.enumerated() {
                    let candidate = self.hashSingleAsset(asset, manager: manager, options: requestOptions)
                    candidates.append(candidate)

                    if (idx + 1) % 5 == 0 || (idx + 1) == totalCount {
                        progressHandler?(idx + 1, totalCount)
                    }
                }

                continuation.resume(returning: candidates)
            }
        }
    }

    /// Hashes a single photo asset synchronously on background worker thread (immune to lost callbacks and deadlocks)
    private func hashSingleAsset(_ asset: PHAsset, manager: PHImageManager, options: PHImageRequestOptions) -> ScannedCandidate {
        let isScreenshot = asset.mediaSubtypes.contains(.photoScreenshot)
        let isBurst = (asset.burstIdentifier != nil)
        let isVideo = (asset.mediaType == .video)

        let pixelTotal = asset.pixelWidth * asset.pixelHeight
        let fileSize: UInt64
        if isVideo {
            // Standard iPhone HEVC 1080p/4K video bitrate is ~25 to 50 Mbps (approx 3.5 MB per second)
            fileSize = UInt64(max(8_000_000, asset.duration * 3_500_000))
        } else if isScreenshot {
            fileSize = UInt64(Float(pixelTotal) * 0.30)
        } else if asset.mediaSubtypes.contains(.photoHDR) {
            fileSize = UInt64(Float(pixelTotal) * 0.65)
        } else {
            fileSize = UInt64(max(1_500_000, Int(Float(pixelTotal) * 0.35)))
        }

        let pixelCount = Float(asset.pixelWidth * asset.pixelHeight)
        let resolutionScore = min(1.0, pixelCount / (4032.0 * 3024.0))
        let burstPenalty: Float = isBurst ? 0.2 : 0.0
        let videoShortPenalty: Float = isVideo && asset.duration < 2.0 ? 0.3 : 0.0
        let quality = max(0.1, resolutionScore - burstPenalty - videoShortPenalty)

        // Request 256px thumbnail synchronously on background thread (Zero continuation deadlock)
        var fetchedImage: UIImage? = nil
        manager.requestImage(
            for: asset,
            targetSize: CGSize(width: 256, height: 256),
            contentMode: .aspectFill,
            options: options
        ) { img, _ in
            fetchedImage = img
        }

        var hashWords: [UInt32] = [0, 0, 0, 0]
        var hasValidHash = false

        if let cgImage = fetchedImage?.cgImage {
            let request = VNGenerateImageFeaturePrintRequest()
            request.revision = VNGenerateImageFeaturePrintRequestRevision2 // Pin to 768-dim deterministic output
            request.imageCropAndScaleOption = .centerCrop
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

            do {
                try handler.perform([request])
                if let observation = request.results?.first as? VNFeaturePrintObservation {
                    let floatCount = observation.elementCount
                    var floatBuffer = [Float](repeating: 0.0, count: floatCount)
                    observation.data.withUnsafeBytes { rawPtr in
                        if let base = rawPtr.baseAddress?.assumingMemoryBound(to: Float.self) {
                            for k in 0..<floatCount { floatBuffer[k] = base[k] }
                        }
                    }

                    if floatCount > 0 {
                        var sumSq: Float = 0.0
                        vDSP_svesq(floatBuffer, 1, &sumSq, vDSP_Length(floatCount))
                        if sumSq > 1e-12 {
                            var norm = sqrt(sumSq)
                            vDSP_vsdiv(floatBuffer, 1, &norm, &floatBuffer, 1, vDSP_Length(floatCount))
                        }

                        hashWords = SimHashProjector.shared.generateSimHash(from: floatBuffer)
                        hasValidHash = true
                    }
                }
            } catch {
                hasValidHash = false
            }
        }

        return ScannedCandidate(
            localIdentifier: asset.localIdentifier,
            hashWords: hashWords,
            qualityScore: quality,
            fileBytes: fileSize,
            creationDate: asset.creationDate,
            isScreenshot: isScreenshot,
            isBurst: isBurst,
            hasValidVisualHash: hasValidHash
        )
    }

    /// Counts all non-favorite photos and videos in the library (fast, no hashing)
    public func fetchLibraryPhotoCount() async -> Int {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let options = PHFetchOptions()
                options.includeHiddenAssets = false
                let assets = PHAsset.fetchAssets(with: options)
                var count = 0
                assets.enumerateObjects { asset, _, _ in
                    if !asset.isFavorite { count += 1 }
                }
                continuation.resume(returning: count)
            }
        }
    }

    /// Scans and hashes media strictly within a specific user album or smart album for per-album curation
    public func scanAlbumCandidates(
        collection: PHAssetCollection,
        progressHandler: ((Int, Int) -> Void)? = nil
    ) async -> [ScannedCandidate] {
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        fetchOptions.includeHiddenAssets = false

        let assets = PHAsset.fetchAssets(in: collection, options: fetchOptions)
        let totalCount = assets.count
        guard totalCount > 0 else { return [] }

        var allIds: [String] = []
        var validAssets: [PHAsset] = []
        assets.enumerateObjects { asset, _, _ in
            if asset.isFavorite { return }
            if PareTrashManager.shared.isAssetProtected(asset.localIdentifier) { return }
            allIds.append(asset.localIdentifier)
            validAssets.append(asset)
        }

        // Fast indexed query: ONLY query the assets that belong to this specific album
        let persisted = PareStorage.shared.loadPersistedCandidates(for: allIds)
        let persistedMap = Dictionary(uniqueKeysWithValues: persisted.map { ($0.localIdentifier, $0) })

        var newToHash: [PHAsset] = []
        var resultCandidates: [ScannedCandidate] = []

        for asset in validAssets {
            if let p = persistedMap[asset.localIdentifier] {
                resultCandidates.append(p)
            } else {
                newToHash.append(asset)
            }
        }

        if newToHash.isEmpty {
            progressHandler?(resultCandidates.count, resultCandidates.count)
            return resultCandidates
        }

        let newlyHashed = await hashAssets(newToHash, progressHandler: progressHandler)
        PareStorage.shared.upsertAssetHashes(newlyHashed)
        return resultCandidates + newlyHashed
    }

    /// Estimates real library clutter volume from screenshots, videos, and bursts off the main thread
    public func estimateLibraryClutter() async -> (totalBytes: Int64, count: Int) {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let options = PHFetchOptions()
                options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
                options.includeHiddenAssets = false
                let assets = PHAsset.fetchAssets(with: options)

                var clutterBytes: Int64 = 0
                var count = 0
                var prevDate: Date? = nil

                assets.enumerateObjects { asset, _, _ in
                    guard !asset.isFavorite else { return }
                    let isScreenshot = asset.mediaSubtypes.contains(.photoScreenshot)
                    let isScreenRecording = asset.mediaSubtypes.contains(.videoScreenRecording)
                    let isBurst = (asset.burstIdentifier != nil)
                    let isVideo = (asset.mediaType == .video)
                    var isConsecutiveDupe = false

                    if let d = asset.creationDate {
                        if let prev = prevDate, abs(d.timeIntervalSince(prev)) <= 3.0 {
                            isConsecutiveDupe = true
                        }
                        prevDate = d
                    }

                    if isScreenshot || isScreenRecording || isBurst || isConsecutiveDupe || (isVideo && asset.duration < 3.0) {
                        count += 1
                        let sz: Int64
                        if isVideo {
                            sz = Int64(max(8_000_000, asset.duration * 3_500_000))
                        } else if isScreenshot {
                            let px = asset.pixelWidth * asset.pixelHeight
                            sz = Int64(Double(px) * 0.30)
                        } else {
                            let px = asset.pixelWidth * asset.pixelHeight
                            sz = Int64(Double(px) * 0.38)
                        }
                        clutterBytes += max(1_200_000, sz)
                    }
                }

                continuation.resume(returning: (clutterBytes, count))
            }
        }
    }

    /// Fetches a high-performance thumbnail for the review deck
    public func fetchThumbnail(for localIdentifier: String, targetSize: CGSize = CGSize(width: 320, height: 380)) async -> UIImage? {
        return await withCheckedContinuation { continuation in
            let assets = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
            guard let asset = assets.firstObject else {
                continuation.resume(returning: nil)
                return
            }

            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = false
            options.resizeMode = .fast

            PHImageManager.default().requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFill,
                options: options
            ) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }

    /// Fetches miniature snapshot thumbnails of gallery media for live 3D orbital animation in the scanning vortex
    public func fetchRecentThumbnails(count: Int = 14) async -> [UIImage] {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let options = PHFetchOptions()
                options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
                options.fetchLimit = count * 2
                options.includeHiddenAssets = false

                let assets = PHAsset.fetchAssets(with: options)
                var images: [UIImage] = []
                let manager = PHImageManager.default()
                let req = PHImageRequestOptions()
                req.isSynchronous = true
                req.isNetworkAccessAllowed = false
                req.deliveryMode = .fastFormat
                req.resizeMode = .fast

                assets.enumerateObjects { asset, _, stop in
                    if images.count >= count {
                        stop.pointee = true
                        return
                    }
                    manager.requestImage(
                        for: asset,
                        targetSize: CGSize(width: 120, height: 120),
                        contentMode: .aspectFill,
                        options: req
                    ) { img, _ in
                        if let img = img {
                            images.append(img)
                        }
                    }
                }
                continuation.resume(returning: images)
            }
        }
    }
}
