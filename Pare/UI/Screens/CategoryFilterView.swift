// CategoryFilterView.swift - Real PhotoKit Smart Category & Media Subtype Pruner
import SwiftUI
import Photos

public enum PhotoClutterCategory: String, CaseIterable, Identifiable {
    case screenshots = "Screenshots"
    case screenRecordings = "Screen Recordings"
    case largeVideos = "Videos"
    case bursts = "Camera Bursts"
    case panoramas = "Panoramas"
    case duplicateTimestamps = "Rapid Snaps"

    public var id: String { rawValue }

    public var systemIcon: String {
        switch self {
        case .screenshots: return "camera.viewfinder"
        case .screenRecordings: return "record.circle"
        case .largeVideos: return "video.fill"
        case .bursts: return "square.stack.3d.down.right.fill"
        case .panoramas: return "pano.fill"
        case .duplicateTimestamps: return "clock.arrow.2.circlepath"
        }
    }
}

public struct InspectingPhotoItem: Identifiable {
    public let id: String
    public let asset: PHAsset
}

public struct CategoryFilterView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    public let isPresentedAsSheet: Bool
    @State private var selectedCategory: PhotoClutterCategory
    @State private var matchedAssetIDs: [String] = []
    @State private var totalFoundCount: Int = 0
    @State private var thumbnails: [String: UIImage] = [:]
    @State private var isLoading: Bool = false
    @State private var categoryBytes: Int64 = 0
    @State private var showConfirmDelete: Bool = false
    @State private var inspectingPhoto: InspectingPhotoItem? = nil

    public init(initialCategory: PhotoClutterCategory = .screenshots, isPresentedAsSheet: Bool = false) {
        self._selectedCategory = State(initialValue: initialCategory)
        self.isPresentedAsSheet = isPresentedAsSheet
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                ParePalette.canvasBackground
                    .ignoresSafeArea()

                VStack(spacing: 16) {
                    // Header Bar
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Categories")
                                .font(.system(size: 26, weight: .heavy, design: .rounded))
                                .foregroundStyle(ParePalette.textPrimary)
                            Text("Choose what to clean")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(ParePalette.textSecondary)
                        }

                        Spacer()

                        if isPresentedAsSheet {
                            Button {
                                dismiss()
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(ParePalette.textSecondary)
                                    .padding(8)
                                    .background(
                                        Circle().fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.06))
                                    )
                            }
                            .buttonStyle(ScalePressStyle())
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 16)

                    // Native Fluid Category Selector Pills
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(PhotoClutterCategory.allCases) { cat in
                                let isSelected = (selectedCategory == cat)
                                Button {
                                    selectedCategory = cat
                                    #if canImport(UIKit)
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    #endif
                                    loadAssets(for: cat)
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: cat.systemIcon)
                                            .font(.system(size: 12, weight: isSelected ? .bold : .medium))
                                        Text(cat.rawValue)
                                            .font(.system(size: 12, weight: isSelected ? .bold : .medium, design: .rounded))
                                    }
                                    .foregroundStyle(isSelected ? Color.white : ParePalette.textSecondary)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background {
                                        if isSelected {
                                            Capsule()
                                                .fill(ParePalette.accent)
                                                .shadow(color: ParePalette.accent.opacity(colorScheme == .dark ? 0.40 : 0.25), radius: 5, x: 0, y: 2)
                                        } else {
                                            Capsule()
                                                .fill(colorScheme == .dark ? Color.white.opacity(0.07) : Color.black.opacity(0.05))
                                        }
                                    }
                                }
                                .buttonStyle(ScalePressStyle())
                            }
                        }
                        .padding(.horizontal, 24)
                    }

                    // Reclaimable Category Status Row
                    HStack {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(matchedAssetIDs.isEmpty ? ParePalette.successGreen : ParePalette.accent)
                                .frame(width: 6, height: 6)

                            Text(totalFoundCount > matchedAssetIDs.count
                                 ? "\(matchedAssetIDs.count) of \(totalFoundCount) items • ~\(String(format: "%.1f MB", Double(categoryBytes) / 1_048_576.0))"
                                 : "\(matchedAssetIDs.count) items • ~\(String(format: "%.1f MB", Double(categoryBytes) / 1_048_576.0))")
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(ParePalette.textSecondary)
                        }

                        Spacer()

                        if !matchedAssetIDs.isEmpty {
                            Button {
                                showConfirmDelete = true
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "trash.fill")
                                        .font(.system(size: 10))
                                    Text("Delete All")
                                        .font(.system(size: 11, weight: .bold, design: .rounded))
                                }
                                .foregroundStyle(ParePalette.alertRed)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(ParePalette.alertRed.opacity(0.12), in: Capsule())
                            }
                            .buttonStyle(ScalePressStyle())
                        }
                    }
                    .padding(.horizontal, 24)

                    // Results Viewport Grid
                    ScrollView {
                        if isLoading {
                            ProgressView().tint(.white).padding(.top, 80)
                        } else if matchedAssetIDs.isEmpty {
                            VStack(spacing: 12) {
                                Spacer(minLength: 80)
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 48))
                                    .foregroundStyle(ParePalette.successGreen)
                                Text("No \(selectedCategory.rawValue) Found")
                                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                                    .foregroundStyle(ParePalette.textPrimary)
                                Text("Everything in this category is clean.")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
                                ForEach(matchedAssetIDs, id: \.self) { assetId in
                                    Button {
                                        let fetched = PHAsset.fetchAssets(withLocalIdentifiers: [assetId], options: nil)
                                        if let first = fetched.firstObject {
                                            self.inspectingPhoto = InspectingPhotoItem(id: assetId, asset: first)
                                        }
                                    } label: {
                                        Color.clear
                                            .aspectRatio(1.0, contentMode: .fit)
                                            .overlay {
                                                if let thumb = thumbnails[assetId] {
                                                    #if canImport(UIKit)
                                                    Image(uiImage: thumb)
                                                        .resizable()
                                                        .aspectRatio(contentMode: .fill)
                                                    #elseif canImport(AppKit)
                                                    Image(nsImage: thumb)
                                                        .resizable()
                                                        .aspectRatio(contentMode: .fill)
                                                    #endif
                                                } else {
                                                    Rectangle()
                                                        .fill(Color.white.opacity(0.06))
                                                }
                                            }
                                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    }
                                    .buttonStyle(ScalePressStyle())
                                    .task {
                                        if thumbnails[assetId] == nil {
                                            thumbnails[assetId] = await ParePhotoScanner.shared.fetchThumbnail(
                                                for: assetId, targetSize: CGSize(width: 320, height: 320)
                                            )
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.bottom, 96) // Guaranteed clearance above floating bottom tab bar
                        }
                    }
                }
            }
            .onAppear {
                loadAssets(for: selectedCategory)
            }
            .fullScreenCover(item: $inspectingPhoto) { item in
                PhotoViewerModal(asset: item.asset, onDelete: {
                    loadAssets(for: selectedCategory)
                })
            }
            .confirmationDialog(
                "Delete All \(selectedCategory.rawValue)?",
                isPresented: $showConfirmDelete,
                titleVisibility: .visible
            ) {
                Button("Delete \(matchedAssetIDs.count) Items", role: .destructive) {
                    Task {
                        let orchestrator = PareOrchestrator.shared
                        let deletedCount = (try? await PareTrashManager.shared.softDeleteAssets(localIdentifiers: matchedAssetIDs)) ?? 0

                        if deletedCount > 0 {
                            orchestrator.recordReclaimedBytes(categoryBytes, count: deletedCount)
                        }

                        loadAssets(for: selectedCategory)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Photos will be moved to your Recently Deleted folder where you can recover them for 30 days.")
            }
        }
    }

    private func loadAssets(for category: PhotoClutterCategory) {
        self.isLoading = true
        self.thumbnails.removeAll()

        Task {
            let fetchOptions = PHFetchOptions()
            // For rapid snaps, chronological order is required to detect consecutive shutter fires
            fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: (category == .duplicateTimestamps))]
            fetchOptions.fetchLimit = 300
            fetchOptions.includeHiddenAssets = false

            // Query .video for Screen Recordings & Videos so video assets actually resolve
            let assets: PHFetchResult<PHAsset>
            if category == .screenRecordings || category == .largeVideos {
                assets = PHAsset.fetchAssets(with: .video, options: fetchOptions)
            } else {
                assets = PHAsset.fetchAssets(with: .image, options: fetchOptions)
            }

            var ids: [String] = []
            var totalBytes: Int64 = 0

            func assetSize(_ a: PHAsset) -> Int64 {
                if a.mediaType == .video {
                    return Int64(max(8_000_000, a.duration * 3_500_000))
                }
                let px = a.pixelWidth * a.pixelHeight
                if a.mediaSubtypes.contains(.photoScreenshot) {
                    return Int64(max(800_000, Double(px) * 0.30))
                } else if a.mediaSubtypes.contains(.photoHDR) {
                    return Int64(max(2_000_000, Double(px) * 0.65))
                } else {
                    return Int64(max(1_500_000, Double(px) * 0.35))
                }
            }

            if category == .duplicateTimestamps {
                // FIX: Real rapid-snaps detection based on consecutive capture timestamps (<= 3.0 seconds)
                var prevDate: Date? = nil
                var prevAsset: PHAsset? = nil

                assets.enumerateObjects { asset, _, _ in
                    guard !asset.isFavorite else { return }
                    if let date = asset.creationDate {
                        if let prev = prevDate, abs(date.timeIntervalSince(prev)) <= 3.0 {
                            if let pAsset = prevAsset, !ids.contains(pAsset.localIdentifier) {
                                ids.append(pAsset.localIdentifier)
                                totalBytes += assetSize(pAsset)
                            }
                            if !ids.contains(asset.localIdentifier) {
                                ids.append(asset.localIdentifier)
                                totalBytes += assetSize(asset)
                            }
                        }
                        prevDate = date
                        prevAsset = asset
                    }
                }
            } else {
                assets.enumerateObjects { asset, _, _ in
                    guard !asset.isFavorite else { return }

                    let matches: Bool = switch category {
                    case .screenshots:
                        asset.mediaSubtypes.contains(.photoScreenshot)
                    case .screenRecordings:
                        asset.mediaSubtypes.contains(.videoScreenRecording)
                    case .largeVideos:
                        asset.mediaType == .video
                    case .bursts:
                        asset.burstIdentifier != nil
                    case .panoramas:
                        asset.mediaSubtypes.contains(.photoPanorama)
                    case .duplicateTimestamps:
                        false
                    }

                    if matches {
                        ids.append(asset.localIdentifier)
                        totalBytes += assetSize(asset)
                    }
                }
            }

            self.matchedAssetIDs = ids
            self.totalFoundCount = assets.count
            self.categoryBytes = totalBytes
            self.isLoading = false
        }
    }
}
