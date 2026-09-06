// PareTrashManager.swift - Non-Destructive Soft-Deletion & Safety Enclave
import Foundation
import Photos

public final class PareTrashManager: @unchecked Sendable {
    public static let shared = PareTrashManager()
    
    private var protectedAssetIdentifiers = Set<String>()
    private var protectedAlbumIdentifiers = Set<String>()
    private var resolvedProtectedAssetIDs = Set<String>()
    private let lock = NSLock()

    private init() {
        if let savedAssets = UserDefaults.standard.stringArray(forKey: "pare_protected_assets") {
            self.protectedAssetIdentifiers = Set(savedAssets)
        }
        if let savedAlbums = UserDefaults.standard.stringArray(forKey: "pare_protected_album_ids") {
            self.protectedAlbumIdentifiers = Set(savedAlbums)
        }
        self.refreshProtectedAssetCache()
    }

    /// Re-queries PhotoKit to resolve all asset IDs belonging to protected albums
    public func refreshProtectedAssetCache() {
        lock.lock()
        defer { lock.unlock() }

        var allProtected = protectedAssetIdentifiers
        for albumID in protectedAlbumIdentifiers {
            let collections = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [albumID], options: nil)
            if let album = collections.firstObject {
                let assets = PHAsset.fetchAssets(in: album, options: nil)
                assets.enumerateObjects { asset, _, _ in
                    allProtected.insert(asset.localIdentifier)
                }
            }
        }
        self.resolvedProtectedAssetIDs = allProtected
    }

    /// Registers a set of album identifiers whose contents the engine must strictly NEVER touch
    public func setProtectedAlbums(_ albumIDs: Set<String>) {
        lock.lock()
        self.protectedAlbumIdentifiers = albumIDs
        UserDefaults.standard.set(Array(albumIDs), forKey: "pare_protected_album_ids")
        lock.unlock()
        refreshProtectedAssetCache()
    }

    public func getProtectedAlbumIDs() -> Set<String> {
        lock.lock()
        defer { lock.unlock() }
        return protectedAlbumIdentifiers
    }

    /// Registers individual asset identifiers that must never be deleted
    public func setProtectedAssets(_ identifiers: Set<String>) {
        lock.lock()
        self.protectedAssetIdentifiers = identifiers
        UserDefaults.standard.set(Array(identifiers), forKey: "pare_protected_assets")
        lock.unlock()
        refreshProtectedAssetCache()
    }

    /// Fast lookup checking if a photo is inside the protected enclave
    public func isAssetProtected(_ assetID: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return resolvedProtectedAssetIDs.contains(assetID)
    }

    private func filterSafeIdentifiers(_ ids: [String]) -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return ids.filter { !resolvedProtectedAssetIDs.contains($0) }
    }

    /**
     * Executes safe, reversible soft-deletion using native PhotoKit change requests.
     * Assets are moved to Apple's "Recently Deleted" album with a 30-day recovery window.
     * Permanent deletion is strictly forbidden.
     *
     * @param localIdentifiers Array of photo local identifiers to trash
     * @return Number of successfully trashed items
     */
    public func softDeleteAssets(localIdentifiers: [String]) async throws -> Int {
        refreshProtectedAssetCache()
        let safeIdentifiers = filterSafeIdentifiers(localIdentifiers)
        guard !safeIdentifiers.isEmpty else { return 0 }

        return try await withCheckedThrowingContinuation { continuation in
            PHPhotoLibrary.shared().performChanges({
                let assets = PHAsset.fetchAssets(withLocalIdentifiers: safeIdentifiers, options: nil)
                PHAssetChangeRequest.deleteAssets(assets)
            }, completionHandler: { success, error in
                if success {
                    PareStorage.shared.removeAssets(localIdentifiers: safeIdentifiers)
                    continuation.resume(returning: safeIdentifiers.count)
                } else {
                    continuation.resume(throwing: error ?? NSError(
                        domain: "com.pare.trash",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "Failed to perform PhotoKit soft delete transaction."]
                    ))
                }
            })
        }
    }
}
