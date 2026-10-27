import Foundation
import CryptoKit

struct FileItem: Identifiable, Hashable, Sendable {
    let id: String          // file path on Mac, PHAsset.localIdentifier on iOS
    let name: String
    let size: Int64
    let folder: String
    let isVideo: Bool
    let date: Date?
    var url: URL { URL(fileURLWithPath: id) }
}

struct DupGroup: Identifiable, Sendable {
    var items: [FileItem]
    var id: String { items.first?.id ?? UUID().uuidString }
    var reclaimable: Int64 { items.dropFirst().reduce(0) { $0 + $1.size } }
}

struct FolderInfo: Identifiable, Hashable, Sendable {
    let path: String
    let count: Int
    let bytes: Int64
    var id: String { path }
    var name: String { (path as NSString).lastPathComponent }
}

func readable(_ bytes: Int64) -> String {
    let f = ByteCountFormatter()
    f.countStyle = .file
    return f.string(fromByteCount: bytes)
}

func hex(_ digest: SHA256.Digest) -> String { digest.map { String(format: "%02x", $0) }.joined() }

/// Size -> head hash -> full hash. Only items that survive each stage are read in full.
enum DupFinder {
    static func find(
        _ items: [FileItem],
        head: @escaping @Sendable (FileItem) async -> String?,
        full: @escaping @Sendable (FileItem) async -> String?,
        progress: @escaping @Sendable (Double) -> Void
    ) async -> [DupGroup] {
        struct K: Hashable { let video: Bool; let size: Int64; let hash: String }
        let sameSize = Dictionary(grouping: items.filter { $0.size > 0 }, by: { "\($0.isVideo)-\($0.size)" })
            .values.filter { $0.count > 1 }.flatMap { $0 }
        let counter = Counter()
        let total1 = max(sameSize.count, 1)
        let h1 = await mapLimited(sameSize, limit: 6) { item in
            let r = await head(item); progress(Double(counter.bump()) / Double(total1) * 0.4); return r
        }
        let survivors = Dictionary(grouping: h1.compactMap { (i, h) in h.map { (i, K(video: i.isVideo, size: i.size, hash: $0)) } }, by: { $0.1 })
            .values.filter { $0.count > 1 }.flatMap { $0.map { $0.0 } }
        counter.reset()
        let total2 = max(survivors.count, 1)
        let h2 = await mapLimited(survivors, limit: 4) { item in
            let r = await full(item); progress(0.4 + Double(counter.bump()) / Double(total2) * 0.6); return r
        }
        progress(1)
        return Dictionary(grouping: h2.compactMap { (i, h) in h.map { (i, K(video: i.isVideo, size: i.size, hash: $0)) } }, by: { $0.1 })
            .values.filter { $0.count > 1 }
            .map { DupGroup(items: $0.map { $0.0 }.sorted(by: keepOrder)) }
            .sorted { $0.reclaimable > $1.reclaimable }
    }

    private static let generic = ["download", "desktop", "screenshot", "camera", "whatsapp"]
    private static func rank(_ i: FileItem) -> Int { generic.contains { i.folder.lowercased().contains($0) } ? 1 : 0 }
    /// Best copy to keep sorts first: outside generic folders, then oldest, then shortest name.
    static func keepOrder(_ a: FileItem, _ b: FileItem) -> Bool {
        if rank(a) != rank(b) { return rank(a) < rank(b) }
        if let x = a.date, let y = b.date, x != y { return x < y }
        return a.name.count < b.name.count
    }

    private static func mapLimited(_ items: [FileItem], limit: Int, _ f: @escaping @Sendable (FileItem) async -> String?) async -> [(FileItem, String?)] {
        await withTaskGroup(of: (Int, String?).self) { g in
            var next = 0
            var res = [String?](repeating: nil, count: items.count)
            func add() {
                guard next < items.count else { return }
                let i = next; next += 1
                g.addTask { (i, await f(items[i])) }
            }
            for _ in 0..<min(limit, items.count) { add() }
            while let (i, r) = await g.next() { res[i] = r; add() }
            return zip(items, res).map { ($0, $1) }
        }
    }
}

final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var n = 0
    func bump() -> Int { lock.lock(); defer { lock.unlock() }; n += 1; return n }
    func reset() { lock.lock(); n = 0; lock.unlock() }
}

@MainActor
protocol LibraryStore: ObservableObject {
    var groups: [DupGroup] { get }
    var selected: Set<String> { get }
    var scanning: Bool { get }
    var scanned: Bool { get }
    var progress: Double { get }
    var label: String { get }
    var photoCount: Int { get }
    var videoCount: Int { get }
    var mediaBytes: Int64 { get }
    var diskTotal: Int64 { get }
    var diskUsed: Int64 { get }
    var message: String? { get }
    var removeVerb: String { get }
    func scan()
    func toggle(_ id: String)
    func autoSelect()
    func clearSelection()
    func removeSelected() async
    func thumbnail(for item: FileItem) async -> PlatformImage?
}

extension LibraryStore {
    var reclaimable: Int64 { groups.reduce(0) { $0 + $1.reclaimable } }
    var copies: Int { groups.reduce(0) { $0 + $1.items.count - 1 } }
    var selectedBytes: Int64 { groups.flatMap { $0.items }.filter { selected.contains($0.id) }.reduce(0) { $0 + $1.size } }
}

func volumeStats() -> (total: Int64, used: Int64) {
    let url = URL(fileURLWithPath: NSHomeDirectory())
    let v = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey])
    let total = Int64(v?.volumeTotalCapacity ?? 0)
    let free = v?.volumeAvailableCapacityForImportantUsage ?? 0
    return (total, max(total - free, 0))
}
