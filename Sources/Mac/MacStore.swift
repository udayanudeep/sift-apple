#if os(macOS)
import SwiftUI
import AppKit
import CryptoKit
import QuickLookThumbnailing

struct CacheEntry: Identifiable, Hashable, Sendable {
    let path: String
    let size: Int64
    var id: String { path }
    var name: String { (path as NSString).lastPathComponent }
}

@MainActor
final class MacStore: ObservableObject, LibraryStore {
    @Published var groups: [DupGroup] = []
    @Published var selected: Set<String> = []
    @Published var scanning = false
    @Published var scanned = false
    @Published var progress = 0.0
    @Published var label = ""
    @Published var items: [FileItem] = []
    @Published var folders: [FolderInfo] = []
    @Published var selFolders: Set<String> = []
    @Published var caches: [CacheEntry] = []
    @Published var selCaches: Set<String> = []
    @Published var loadingCaches = false
    @Published var roots: [URL] = MacStore.defaultRoots()
    @Published var diskTotal: Int64 = 0
    @Published var diskUsed: Int64 = 0
    @Published var message: String?

    var removeVerb: String { "Move to Trash" }
    var photoCount: Int { items.filter { !$0.isVideo }.count }
    var videoCount: Int { items.filter { $0.isVideo }.count }
    var mediaBytes: Int64 { items.reduce(0) { $0 + $1.size } }

    init() { refreshDisk() }

    static func defaultRoots() -> [URL] {
        let fm = FileManager.default
        return [.picturesDirectory, .moviesDirectory, .downloadsDirectory, .desktopDirectory]
            .compactMap { fm.urls(for: $0, in: .userDomainMask).first }
            .filter { fm.fileExists(atPath: $0.path) }
    }

    func refreshDisk() { let s = volumeStats(); diskTotal = s.total; diskUsed = s.used }

    func addRoot() {
        let p = NSOpenPanel()
        p.canChooseDirectories = true; p.canChooseFiles = false; p.allowsMultipleSelection = true
        if p.runModal() == .OK { for u in p.urls where !roots.contains(u) { roots.append(u) } }
    }
    func removeRoot(_ u: URL) { roots.removeAll { $0 == u } }

    // MARK: scan
    private static let photoExt: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "gif", "tiff", "tif", "webp", "dng", "cr2", "nef", "arw", "raw"]
    private static let videoExt: Set<String> = ["mp4", "mov", "m4v", "mkv", "avi", "3gp", "mts"]

    nonisolated static func enumerate(_ roots: [URL]) -> [FileItem] {
        var out: [FileItem] = []
        var seen = Set<String>()
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]
        for root in roots {
            guard let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            for case let u as URL in e {
                let ext = u.pathExtension.lowercased()
                let isVideo = videoExt.contains(ext)
                guard isVideo || photoExt.contains(ext) else { continue }
                guard let v = try? u.resourceValues(forKeys: Set(keys)), v.isRegularFile == true, let size = v.fileSize, size > 0 else { continue }
                guard seen.insert(u.path).inserted else { continue }
                out.append(FileItem(id: u.path, name: u.lastPathComponent, size: Int64(size), folder: u.deletingLastPathComponent().path, isVideo: isVideo, date: v.contentModificationDate))
            }
        }
        return out
    }

    nonisolated static func fileHash(_ path: String, limit: Int?) -> String? {
        guard let h = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? h.close() }
        var sha = SHA256()
        var left = limit ?? Int.max
        while left > 0 {
            guard let d = try? h.read(upToCount: min(1 << 20, left)), !d.isEmpty else { break }
            sha.update(data: d); left -= d.count
        }
        return hex(sha.finalize())
    }

    func scan() {
        guard !scanning else { return }
        scanning = true; progress = 0; label = "Reading folders"; selected = []; selFolders = []; message = nil
        let roots = roots
        Task {
            let found = await Task.detached { MacStore.enumerate(roots) }.value
            items = found
            folders = Dictionary(grouping: found, by: { $0.folder })
                .map { FolderInfo(path: $0.key, count: $0.value.count, bytes: $0.value.reduce(0) { $0 + $1.size }) }
                .sorted { $0.bytes > $1.bytes }
            label = "Comparing files"
            let me = self
            groups = await DupFinder.find(found,
                head: { i in await Task.detached { MacStore.fileHash(i.id, limit: 256 * 1024) }.value },
                full: { i in await Task.detached { MacStore.fileHash(i.id, limit: nil) }.value },
                progress: { p in Task { @MainActor in me.progress = p } })
            scanning = false; scanned = true; label = ""; refreshDisk()
        }
    }

    func toggle(_ id: String) { if !selected.insert(id).inserted { selected.remove(id) } }
    func autoSelect() { selected = Set(groups.flatMap { $0.items.dropFirst() }.map(\.id)) }
    func clearSelection() { selected = [] }

    /// Moves to the Trash only. Nothing is permanently deleted.
    func removeSelected() async {
        var moved = 0, bytes: Int64 = 0
        let byId = Dictionary(uniqueKeysWithValues: groups.flatMap { $0.items }.map { ($0.id, $0) })
        for id in selected {
            guard let it = byId[id] else { continue }
            if (try? FileManager.default.trashItem(at: it.url, resultingItemURL: nil)) != nil { moved += 1; bytes += it.size }
        }
        let gone = selected
        items.removeAll { gone.contains($0.id) }
        groups = groups.map { DupGroup(items: $0.items.filter { !gone.contains($0.id) }) }.filter { $0.items.count > 1 }
        selected = []
        message = "Moved \(moved) files (\(readable(bytes))) to the Trash"
        refreshDisk()
    }

    func thumbnail(for item: FileItem) async -> PlatformImage? {
        let req = QLThumbnailGenerator.Request(fileAt: item.url, size: CGSize(width: 256, height: 256), scale: 2, representationTypes: .thumbnail)
        return try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: req).nsImage
    }

    // MARK: folders
    func toggleFolder(_ p: String) { if !selFolders.insert(p).inserted { selFolders.remove(p) } }

    /// Moves media from the other selected folders into `target`, suffixing names that clash. Never deletes.
    func merge(into target: String) {
        let fm = FileManager.default
        var moved = 0
        for it in items where selFolders.contains(it.folder) && it.folder != target {
            var dest = URL(fileURLWithPath: target).appendingPathComponent(it.name)
            var n = 1
            let base = dest.deletingPathExtension().lastPathComponent, ext = dest.pathExtension
            while fm.fileExists(atPath: dest.path) {
                dest = URL(fileURLWithPath: target).appendingPathComponent(ext.isEmpty ? "\(base)_\(n)" : "\(base)_\(n).\(ext)"); n += 1
            }
            if (try? fm.moveItem(at: it.url, to: dest)) != nil { moved += 1 }
        }
        message = "Moved \(moved) files into \((target as NSString).lastPathComponent)"
        scan()
    }

    // MARK: caches
    func loadCaches() {
        guard !loadingCaches else { return }
        loadingCaches = true
        Task {
            let list: [CacheEntry] = await Task.detached {
                let base = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Caches")
                let kids = (try? FileManager.default.contentsOfDirectory(at: base, includingPropertiesForKeys: nil)) ?? []
                return kids.map { CacheEntry(path: $0.path, size: MacStore.dirSize($0)) }.filter { $0.size > 0 }.sorted { $0.size > $1.size }
            }.value
            caches = list; selCaches = []; loadingCaches = false
        }
    }

    nonisolated static func dirSize(_ url: URL) -> Int64 {
        var total: Int64 = 0
        guard let e = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey], options: []) else {
            return Int64((try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize) ?? 0)
        }
        for case let u as URL in e {
            let v = try? u.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey])
            if v?.isRegularFile == true { total += Int64(v?.totalFileAllocatedSize ?? 0) }
        }
        return total
    }

    func toggleCache(_ p: String) { if !selCaches.insert(p).inserted { selCaches.remove(p) } }
    var selCacheBytes: Int64 { caches.filter { selCaches.contains($0.id) }.reduce(0) { $0 + $1.size } }

    func trashCaches() {
        var moved = 0
        for c in caches where selCaches.contains(c.id) {
            if (try? FileManager.default.trashItem(at: URL(fileURLWithPath: c.path), resultingItemURL: nil)) != nil { moved += 1 }
        }
        message = "Moved \(moved) cache folders to the Trash"
        loadingCaches = false; loadCaches(); refreshDisk()
    }
}
#endif
