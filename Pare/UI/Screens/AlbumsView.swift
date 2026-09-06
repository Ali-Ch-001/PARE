// AlbumsView.swift - High-Speed Native Album Gallery & Dedicated Per-Album Cleaner
import SwiftUI
import Photos
#if canImport(UIKit)
import UIKit
#endif

public struct AlbumItem: Identifiable, Hashable {
    public let id: String
    public let title: String
    public let count: Int
    public let collection: PHAssetCollection
    public let coverAssetId: String?

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    public static func == (lhs: AlbumItem, rhs: AlbumItem) -> Bool {
        lhs.id == rhs.id
    }
}

public struct AlbumsView: View {
    @State private var albums: [AlbumItem] = []
    @State private var smartAlbums: [AlbumItem] = []
    @State private var isLoading: Bool = false

    public init() {}

    public var body: some View {
        NavigationStack {
            ZStack {
                ParePalette.canvasBackground
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        // Smart Media Albums Section
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Media Types")
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundStyle(ParePalette.accent)
                                .padding(.horizontal, 24)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(smartAlbums) { album in
                                        NavigationLink(value: album) {
                                            AlbumCoverCard(album: album, width: 140, height: 160)
                                        }
                                        .buttonStyle(ScalePressStyle())
                                    }
                                }
                                .padding(.horizontal, 24)
                            }
                        }

                        // User Albums Grid
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("My Albums")
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                    .foregroundStyle(ParePalette.textPrimary)

                                Spacer()

                                Text("\(albums.count) albums")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(ParePalette.textSecondary)
                            }
                            .padding(.horizontal, 24)

                            if isLoading && albums.isEmpty {
                                HStack {
                                    Spacer()
                                    ProgressView().tint(ParePalette.accent).padding(40)
                                    Spacer()
                                }
                            } else if albums.isEmpty {
                                Text("No albums found.")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 24)
                            } else {
                                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                                    ForEach(albums) { album in
                                        NavigationLink(value: album) {
                                            AlbumCoverCard(album: album, width: nil, height: 180)
                                        }
                                        .buttonStyle(ScalePressStyle())
                                    }
                                }
                                .padding(.horizontal, 24)
                            }
                        }
                    }
                    .padding(.top, 16)
                    .padding(.bottom, 96) // Pad for floating bottom tab bar
                }
            }
            .navigationTitle("Albums")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
            #endif
            .navigationDestination(for: AlbumItem.self) { album in
                AlbumDetailView(album: album)
            }
            .onAppear {
                loadAllAlbums()
            }
        }
    }

    private func loadAllAlbums() {
        if !albums.isEmpty && !smartAlbums.isEmpty { return }
        self.isLoading = true
        DispatchQueue.global(qos: .userInitiated).async {
            var userList: [AlbumItem] = []
            var smartList: [AlbumItem] = []

            // 1. Fetch User Albums (Instant query - zero synchronous decode)
            let userCollections = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: nil)
            userCollections.enumerateObjects { collection, _, _ in
                let assets = PHAsset.fetchAssets(in: collection, options: nil)
                if assets.count > 0 {
                    userList.append(AlbumItem(
                        id: collection.localIdentifier,
                        title: collection.localizedTitle ?? "Untitled",
                        count: assets.count,
                        collection: collection,
                        coverAssetId: assets.lastObject?.localIdentifier
                    ))
                }
            }

            // 2. Fetch Smart Albums (Instant query)
            let smartCollections = PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: .any, options: nil)
            smartCollections.enumerateObjects { collection, _, _ in
                let assets = PHAsset.fetchAssets(in: collection, options: nil)
                if assets.count > 0 {
                    smartList.append(AlbumItem(
                        id: collection.localIdentifier,
                        title: collection.localizedTitle ?? "Media",
                        count: assets.count,
                        collection: collection,
                        coverAssetId: assets.lastObject?.localIdentifier
                    ))
                }
            }

            DispatchQueue.main.async {
                self.albums = userList.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
                self.smartAlbums = smartList
                self.isLoading = false
            }
        }
    }
}

// Album Cover Card (Asynchronous Retina Cover Loader)
struct AlbumCoverCard: View {
    let album: AlbumItem
    let width: CGFloat?
    let height: CGFloat
    @State private var coverImage: UIImage? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .bottomLeading) {
                if let cover = coverImage {
                    #if canImport(UIKit)
                    Image(uiImage: cover)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(maxWidth: width ?? .infinity)
                        .frame(height: height - 50)
                        .clipped()
                    #elseif canImport(AppKit)
                    Image(nsImage: cover)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(maxWidth: width ?? .infinity)
                        .frame(height: height - 50)
                        .clipped()
                    #endif
                } else {
                    Rectangle()
                        .fill(Color.white.opacity(0.06))
                        .frame(maxWidth: width ?? .infinity)
                        .frame(height: height - 50)
                        .overlay {
                            Image(systemName: "photo.on.rectangle")
                                .font(.system(size: 20))
                                .foregroundStyle(.secondary.opacity(0.6))
                        }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .task(id: album.coverAssetId) {
                loadCover()
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(album.title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(ParePalette.textPrimary)
                    .lineLimit(1)

                Text("\(album.count) photos")
                    .font(.system(size: 11))
                    .foregroundStyle(ParePalette.textSecondary)
            }
            .padding(.horizontal, 2)
        }
        .frame(width: width)
    }

    private func loadCover() {
        guard coverImage == nil, let assetId = album.coverAssetId else { return }
        let fetched = PHAsset.fetchAssets(withLocalIdentifiers: [assetId], options: nil)
        guard let asset = fetched.firstObject else { return }

        let req = PHImageRequestOptions()
        req.isSynchronous = false
        req.deliveryMode = .opportunistic
        req.resizeMode = .fast

        PHImageManager.default().requestImage(for: asset, targetSize: CGSize(width: 360, height: 360), contentMode: .aspectFill, options: req) { img, _ in
            if let img = img {
                DispatchQueue.main.async {
                    self.coverImage = img
                }
            }
        }
    }
}

// Dedicated Per-Album Viewer and Clutter Cleaner
public struct AlbumDetailView: View {
    public let album: AlbumItem
    @State private var assets: [PHAsset] = []
    @State private var showProcessing: Bool = false
    @State private var inspectingAsset: InspectingPhotoItem? = nil

    public init(album: AlbumItem) {
        self.album = album
    }

    public var body: some View {
        ZStack {
            ParePalette.canvasBackground
                .ignoresSafeArea()

            VStack(spacing: 16) {
                // Action Bar: Scan & Clean This Specific Album
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(album.title)
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundStyle(ParePalette.textPrimary)
                        Text("\(assets.count) photos")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(ParePalette.textSecondary)
                    }

                    Spacer()

                    Button {
                        runPerAlbumClean()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "sparkles")
                            Text("Clean Album")
                        }
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .primaryActionButton(cornerRadius: 14)
                    }
                    .buttonStyle(ScalePressStyle())
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)

                // High-Performance Zero-Allocation Media Grid (120 FPS)
                ScrollView {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 4), GridItem(.flexible(), spacing: 4), GridItem(.flexible(), spacing: 4)], spacing: 4) {
                        ForEach(assets, id: \.localIdentifier) { asset in
                            Button {
                                self.inspectingAsset = InspectingPhotoItem(id: asset.localIdentifier, asset: asset)
                            } label: {
                                AlbumAssetCell(asset: asset)
                            }
                            .buttonStyle(ScalePressStyle())
                        }
                    }
                    .padding(.horizontal, 4)
                    .padding(.bottom, 36)
                }
            }
        }
        .navigationTitle(album.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear {
            loadAlbumAssets()
        }
        .sheet(isPresented: $showProcessing, onDismiss: {
            loadAlbumAssets()
        }) {
            ProcessingView()
        }
        .fullScreenCover(item: $inspectingAsset) { item in
            PhotoViewerModal(asset: item.asset, onDelete: {
                loadAlbumAssets()
            })
        }
    }

    private func loadAlbumAssets() {
        DispatchQueue.global(qos: .userInitiated).async {
            let fetched = PHAsset.fetchAssets(in: album.collection, options: nil)
            var items: [PHAsset] = []
            items.reserveCapacity(fetched.count)
            fetched.enumerateObjects { asset, _, _ in
                items.append(asset)
            }
            DispatchQueue.main.async {
                self.assets = items
            }
        }
    }

    private func runPerAlbumClean() {
        self.showProcessing = true
        Task {
            await PareOrchestrator.shared.startAlbumCurationPipeline(for: album.collection)
        }
    }
}

// Isolated Cell with Per-Item Thumbnail State (Zero Parent View Invalidation)
struct AlbumAssetCell: View {
    let asset: PHAsset
    @State private var thumbnail: UIImage? = nil

    var body: some View {
        Color.clear
            .aspectRatio(1.0, contentMode: .fit)
            .overlay {
                if let thumb = thumbnail {
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
                    Rectangle().fill(Color.white.opacity(0.06))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(alignment: .bottomTrailing) {
                if asset.mediaType == .video {
                    HStack(spacing: 2) {
                        Image(systemName: "video.fill")
                            .font(.system(size: 8))
                        Text(formatDuration(asset.duration))
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(3)
                    .background(Color.black.opacity(0.65))
                    .clipShape(Capsule())
                    .padding(4)
                }
            }
            .task(id: asset.localIdentifier) {
                loadThumbnail()
            }
    }

    private func loadThumbnail() {
        guard thumbnail == nil else { return }
        let req = PHImageRequestOptions()
        req.isSynchronous = false
        req.deliveryMode = .opportunistic
        req.resizeMode = .fast

        PHImageManager.default().requestImage(
            for: asset,
            targetSize: CGSize(width: 250, height: 250),
            contentMode: .aspectFill,
            options: req
        ) { img, _ in
            if let img = img {
                DispatchQueue.main.async {
                    self.thumbnail = img
                }
            }
        }
    }

    private func formatDuration(_ dur: TimeInterval) -> String {
        let mins = Int(dur) / 60
        let secs = Int(dur) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
