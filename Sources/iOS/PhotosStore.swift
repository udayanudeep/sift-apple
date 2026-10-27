#if os(iOS)
import SwiftUI
import Photos
import CryptoKit

final class ResourceBox: @unchecked Sendable {
    var map: [String: PHAssetResource] = [:]
}

@MainActor
final class PhotosStore: ObservableObject, LibraryStore {
    @Published var groups: [DupGroup] = []
    @Published var selected: Set<String> = []
    @Published var scanning = false
    @Published var scanned = false
    @Published var progress = 0.0
    @Published var label = ""
    @Published var photoCount = 0
    @Published var videoCount = 0
    @Published var mediaBytes: Int64 = 0
    @Published var diskTotal: Int64 = 0
    @Published var diskUsed: Int64 = 0
    @Published var message: String?

    var removeVerb: String { "Delete" }
    private var assets: [String: PHAsset] = [:]
    private let boxes = ResourceBox()

    init() { let s = volumeStats(); diskTotal = s.total; diskUsed = s.used }

    func scan() {
        guard !scanning else { return }
        scanning = true; progress = 0; label = "Reading library"; selected = []; message = nil
        Task {
            let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            guard status == .authorized || status == .limited else {
                scanning = false; message = "Allow Photos access in Settings to scan."; return
            }
            let fetched = PHAsset.fetchAssets(with: nil)
            var items: [FileItem] = []
            assets = [:]; boxes.map = [:]
            fetched.enumerateObjects { asset, _, _ in
                guard asset.mediaType == .image || asset.mediaType == .video else { return }
                let res = PHAssetResource.assetResources(for: asset)
                guard let primary = res.first(where: { $0.type == .photo || $0.type == .video }) ?? res.first else { return }
                let size = (primary.value(forKey: "fileSize") as? NSNumber)?.int64Value ?? 0
                self.assets[asset.localIdentifier] = asset
                self.boxes.map[asset.localIdentifier] = primary
                items.append(FileItem(id: asset.localIdentifier, name: primary.originalFilename, size: size, folder: "", isVideo: asset.mediaType == .video, date: asset.creationDate))
            }
            photoCount = items.filter { !$0.isVideo }.count
            videoCount = items.filter { $0.isVideo }.count
            mediaBytes = items.reduce(0) { $0 + $1.size }
            label = "Comparing files"
            let box = boxes, me = self
            groups = await DupFinder.find(items,
                head: { i in await PhotosStore.hash(box.map[i.id], limit: 256 * 1024) },
                full: { i in await PhotosStore.hash(box.map[i.id], limit: nil) },
                progress: { p in Task { @MainActor in me.progress = p } })
            scanning = false; scanned = true; label = ""
        }
    }

    nonisolated static func hash(_ res: PHAssetResource?, limit: Int?) async -> String? {
        guard let res else { return nil }
        return await withCheckedContinuation { (cont: CheckedContinuation<String?, Never>) in
            var sha = SHA256()
            var count = 0
            var finished = false
            var reqID: PHAssetResourceDataRequestID = 0
            let opts = PHAssetResourceRequestOptions()
            opts.isNetworkAccessAllowed = false
            reqID = PHAssetResourceManager.default().requestData(for: res, options: opts, dataReceivedHandler: { data in
                if finished { return }
                if let limit {
                    let take = min(data.count, limit - count)
                    sha.update(data: data.prefix(take)); count += take
                    if count >= limit {
                        finished = true
                        PHAssetResourceManager.default().cancelDataRequest(reqID)
                        cont.resume(returning: hex(sha.finalize()))
                    }
                } else { sha.update(data: data) }
            }, completionHandler: { err in
                if finished { return }
                finished = true
                cont.resume(returning: err == nil ? hex(sha.finalize()) : nil)
            })
        }
    }

    func toggle(_ id: String) { if !selected.insert(id).inserted { selected.remove(id) } }
    func autoSelect() { selected = Set(groups.flatMap { $0.items.dropFirst() }.map(\.id)) }
    func clearSelection() { selected = [] }

    /// iOS shows its own confirmation; deleted items go to Recently Deleted for 30 days.
    func removeSelected() async {
        let list = selected.compactMap { assets[$0] }
        guard !list.isEmpty else { return }
        do {
            try await PHPhotoLibrary.shared().performChanges { PHAssetChangeRequest.deleteAssets(list as NSArray) }
            let gone = selected
            groups = groups.map { DupGroup(items: $0.items.filter { !gone.contains($0.id) }) }.filter { $0.items.count > 1 }
            message = "Deleted \(list.count) items (kept in Recently Deleted for 30 days)"
            selected = []
        } catch { message = "Nothing deleted." }
    }

    func thumbnail(for item: FileItem) async -> PlatformImage? {
        guard let asset = assets[item.id] else { return nil }
        return await withCheckedContinuation { cont in
            let o = PHImageRequestOptions()
            o.deliveryMode = .highQualityFormat; o.isNetworkAccessAllowed = false; o.resizeMode = .fast
            PHImageManager.default().requestImage(for: asset, targetSize: CGSize(width: 300, height: 300), contentMode: .aspectFill, options: o) { img, _ in cont.resume(returning: img) }
        }
    }
}

struct RootView: View {
    @StateObject private var store = PhotosStore()
    @State private var tab: SiftTab = .overview
    var body: some View {
        ZStack(alignment: .top) {
            Theme.bg.ignoresSafeArea()
            RadialGradient(colors: [Theme.teal.opacity(0.18), .clear], center: .topTrailing, startRadius: 0, endRadius: 500).ignoresSafeArea()
            VStack(spacing: 0) {
                TabBar(tab: $tab).padding(.top, 8)
                switch tab {
                case .duplicates: DuplicatesView(store: store)
                default: OverviewView(store: store)
                }
            }
        }
    }
}
#endif
