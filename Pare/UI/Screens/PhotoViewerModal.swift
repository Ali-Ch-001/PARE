// PhotoViewerModal.swift - High-Resolution Pinch-to-Zoom Inspector with ML Metadata
import SwiftUI
import Photos
#if canImport(UIKit)
import UIKit
#endif

public struct PhotoViewerModal: View {
    @Environment(\.dismiss) private var dismiss
    public let asset: PHAsset
    public var onDelete: (() -> Void)? = nil

    @State private var highResImage: UIImage? = nil
    @State private var isLoading: Bool = true
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var showDeleteConfirm: Bool = false
    @State private var isDeleting: Bool = false
    @State private var fileSizeString: String = "Calculating…"
    @State private var qualityScore: Float? = nil

    public init(asset: PHAsset, onDelete: (() -> Void)? = nil) {
        self.asset = asset
        self.onDelete = onDelete
    }

    public var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            // Centered High-Resolution Pinch-to-Zoom Image Viewport
            GeometryReader { geo in
                ZStack {
                    if let img = highResImage {
                        #if canImport(UIKit)
                        Image(uiImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .scaleEffect(scale)
                            .offset(offset)
                            .gesture(
                                MagnificationGesture()
                                    .onChanged { value in
                                        let delta = value / lastScale
                                        lastScale = value
                                        scale = min(max(scale * delta, 1.0), 5.0)
                                    }
                                    .onEnded { _ in
                                        lastScale = 1.0
                                        if scale < 1.0 {
                                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                                scale = 1.0
                                                offset = .zero
                                            }
                                        }
                                    }
                            )
                            .simultaneousGesture(
                                DragGesture()
                                    .onChanged { value in
                                        if scale > 1.0 {
                                            offset = CGSize(
                                                width: lastOffset.width + value.translation.width,
                                                height: lastOffset.height + value.translation.height
                                            )
                                        } else if value.translation.height > 60 {
                                            // Swipe down to dismiss
                                            dismiss()
                                        }
                                    }
                                    .onEnded { _ in
                                        lastOffset = offset
                                    }
                            )
                            .onTapGesture(count: 2) {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                                    if scale > 1.0 {
                                        scale = 1.0
                                        offset = .zero
                                        lastOffset = .zero
                                    } else {
                                        scale = 2.5
                                    }
                                }
                            }
                        #endif
                    } else {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(1.2)
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }

            // Top Header Overlay
            VStack {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        if let date = asset.creationDate {
                            Text(date.formatted(date: .abbreviated, time: .shortened))
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                        }

                        Text("\(asset.pixelWidth) × \(asset.pixelHeight) • \(fileSizeString)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.7))
                    }

                    Spacer()

                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(10)
                            .background(Circle().fill(Color.white.opacity(0.2)))
                    }
                    .buttonStyle(ScalePressStyle())
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)

                Spacer()

                // Bottom Action Bar: AI Quality Diagnostics & Single Delete
                VStack(spacing: 12) {
                    // AI Quality / Similarity Badge
                    HStack(spacing: 8) {
                        if let score = qualityScore {
                            HStack(spacing: 5) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(score >= 0.6 ? ParePalette.successGreen : ParePalette.heroGold)
                                Text(String(format: "%.0f%% Quality Score", score * 100))
                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.white.opacity(0.12), in: Capsule())
                        }

                        if asset.mediaType == .video {
                            HStack(spacing: 4) {
                                Image(systemName: "video.fill")
                                    .font(.system(size: 11))
                                Text(formatDuration(asset.duration))
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.white.opacity(0.12), in: Capsule())
                        }

                        Spacer()

                        // Delete Single Photo Button
                        Button {
                            showDeleteConfirm = true
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "trash.fill")
                                    .font(.system(size: 12))
                                Text("Delete")
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                            }
                            .foregroundStyle(ParePalette.alertRed)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(ParePalette.alertRed.opacity(0.18), in: Capsule())
                        }
                        .buttonStyle(ScalePressStyle())
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                }
            }
        }
        .task(id: asset.localIdentifier) {
            loadFullResImage()
            calculateFileSize()
            loadQualityScore()
        }
        .confirmationDialog(
            "Move to Recently Deleted?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete Photo", role: .destructive) {
                deleteThisAsset()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This photo will stay in your Recently Deleted album for 30 days before permanent removal.")
        }
    }

    private func loadFullResImage() {
        let req = PHImageRequestOptions()
        req.isSynchronous = false
        req.deliveryMode = .highQualityFormat
        req.resizeMode = .exact
        req.isNetworkAccessAllowed = true

        PHImageManager.default().requestImage(
            for: asset,
            targetSize: CGSize(width: 2000, height: 2000),
            contentMode: .aspectFit,
            options: req
        ) { img, _ in
            if let img = img {
                DispatchQueue.main.async {
                    self.highResImage = img
                    self.isLoading = false
                }
            }
        }
    }

    private func calculateFileSize() {
        let resources = PHAssetResource.assetResources(for: asset)
        var totalBytes: Int64 = 0
        for r in resources {
            if let size = r.value(forKey: "fileSize") as? Int64 {
                totalBytes += size
            }
        }
        if totalBytes > 0 {
            if totalBytes >= 1_048_576 {
                self.fileSizeString = String(format: "%.1f MB", Double(totalBytes) / 1_048_576.0)
            } else {
                self.fileSizeString = "\(totalBytes / 1024) KB"
            }
        } else {
            self.fileSizeString = "Photo"
        }
    }

    private func loadQualityScore() {
        let id = asset.localIdentifier
        let persisted = PareStorage.shared.loadPersistedCandidates(for: [id])
        if let first = persisted.first {
            self.qualityScore = first.qualityScore
        }
    }

    private func deleteThisAsset() {
        Task {
            isDeleting = true
            let count = (try? await PareTrashManager.shared.softDeleteAssets(localIdentifiers: [asset.localIdentifier])) ?? 0
            isDeleting = false
            if count > 0 {
                onDelete?()
                dismiss()
            }
        }
    }

    private func formatDuration(_ dur: TimeInterval) -> String {
        let mins = Int(dur) / 60
        let secs = Int(dur) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}