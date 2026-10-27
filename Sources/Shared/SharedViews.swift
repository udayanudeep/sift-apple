import SwiftUI

struct ThumbnailView<S: LibraryStore>: View {
    let store: S
    let item: FileItem
    @State private var image: PlatformImage?
    var body: some View {
        ZStack {
            Theme.card
            if let image { Image(platform: image).resizable().scaledToFill() }
            else { Image(systemName: item.isVideo ? "play.rectangle" : "photo").foregroundStyle(Theme.dim) }
        }
        .task(id: item.id) { image = await store.thumbnail(for: item) }
    }
}

struct OverviewView<S: LibraryStore>: View {
    @ObservedObject var store: S
    var extra: AnyView = AnyView(EmptyView())

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                HeroCard {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack { Chip(title: store.scanned ? "Scan complete" : "Ready"); Spacer(); Text("sift").font(.num(20)).foregroundStyle(.white.opacity(0.9)) }
                        Spacer().frame(height: 18)
                        Text("RECLAIMABLE").font(.label(11)).tracking(2).foregroundStyle(.white.opacity(0.75))
                        Text(store.scanned ? readable(store.reclaimable) : "—")
                            .font(.num(64)).foregroundStyle(.white).minimumScaleFactor(0.5).lineLimit(1)
                        Text(store.scanned ? "\(store.copies) extra copies in \(store.groups.count) groups" : "Run a scan to find exact duplicates")
                            .font(.label(14)).foregroundStyle(.white.opacity(0.85))
                    }
                    .frame(minHeight: 200, alignment: .topLeading)
                }
                HStack(spacing: 14) {
                    StatCard(title: "Photos", value: store.scanned ? "\(store.photoCount)" : "–", accent: Theme.lime)
                    StatCard(title: "Videos", value: store.scanned ? "\(store.videoCount)" : "–", accent: Theme.teal)
                    StatCard(title: "Library", value: store.scanned ? readable(store.mediaBytes) : "–", accent: .white)
                }
                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Storage").font(.num(18)).foregroundStyle(Theme.ink)
                            Spacer()
                            Text("\(readable(store.diskUsed)) of \(readable(store.diskTotal))").font(.label(12)).foregroundStyle(Theme.dim)
                        }
                        GeometryReader { geo in
                            let used = store.diskTotal > 0 ? CGFloat(store.diskUsed) / CGFloat(store.diskTotal) : 0
                            let media = store.diskTotal > 0 ? CGFloat(store.mediaBytes) / CGFloat(store.diskTotal) : 0
                            ZStack(alignment: .leading) {
                                Capsule().fill(.white.opacity(0.08))
                                Capsule().fill(.white.opacity(0.35)).frame(width: geo.size.width * used)
                                Capsule().fill(Theme.limeGradient).frame(width: max(geo.size.width * media, media > 0 ? 8 : 0))
                            }
                        }.frame(height: 12)
                        HStack(spacing: 16) {
                            Label("Photos & videos", systemImage: "circle.fill").foregroundStyle(Theme.lime)
                            Label("Other used", systemImage: "circle.fill").foregroundStyle(.white.opacity(0.5))
                        }.font(.label(11)).labelStyle(DotLabel())
                    }
                }
                extra
                if store.scanning {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(store.label.uppercased()).font(.label(11)).tracking(1.6).foregroundStyle(Theme.dim)
                            ProgressView(value: store.progress).tint(Theme.lime)
                        }
                    }
                } else {
                    Button(store.scanned ? "Scan again" : "Scan library") { store.scan() }
                        .buttonStyle(PillButtonStyle()).frame(maxWidth: .infinity)
                }
                if let m = store.message { Text(m).font(.label(13)).foregroundStyle(Theme.lime) }
            }
            .padding(24).frame(maxWidth: 860).frame(maxWidth: .infinity)
        }
    }
}

struct DotLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) { configuration.icon.font(.system(size: 7)); configuration.title.foregroundStyle(Theme.dim) }
    }
}

struct DuplicatesView<S: LibraryStore>: View {
    @ObservedObject var store: S
    @State private var confirm = false

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    Text("Duplicates").font(.num(34)).foregroundStyle(Theme.ink)
                    Text(store.scanned ? "\(store.groups.count) groups · \(readable(store.reclaimable)) reclaimable" : "Scan first to find duplicates")
                        .font(.label(14)).foregroundStyle(Theme.dim)
                    if !store.groups.isEmpty {
                        HStack(spacing: 10) {
                            Button("Select all copies") { store.autoSelect() }.buttonStyle(PillButtonStyle(filled: false))
                            Button("Clear") { store.clearSelection() }.buttonStyle(PillButtonStyle(filled: false))
                        }
                    }
                    ForEach(store.groups) { g in
                        GlassCard(padding: 16) {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("\(g.items.count) COPIES · \(readable(g.items[0].size)) EACH").font(.label(10)).tracking(1.4).foregroundStyle(Theme.dim)
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 12) {
                                        ForEach(Array(g.items.enumerated()), id: \.element.id) { idx, m in
                                            tile(m, keep: idx == 0)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    Spacer().frame(height: 110)
                }
                .padding(24).frame(maxWidth: 860).frame(maxWidth: .infinity)
            }
            if !store.selected.isEmpty {
                ActionBar(title: "\(store.selected.count) selected", subtitle: readable(store.selectedBytes), action: store.removeVerb) { confirm = true }
                    .padding(.horizontal, 24).padding(.bottom, 18).frame(maxWidth: 860)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.35), value: store.selected.isEmpty)
        .confirmationDialog("\(store.removeVerb) \(store.selected.count) files (\(readable(store.selectedBytes)))?", isPresented: $confirm, titleVisibility: .visible) {
            Button(store.removeVerb, role: .destructive) { Task { await store.removeSelected() } }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func tile(_ m: FileItem, keep: Bool) -> some View {
        let on = store.selected.contains(m.id)
        return VStack(alignment: .leading, spacing: 6) {
            ThumbnailView(store: store, item: m)
                .frame(width: 128, height: 128)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(on ? Theme.lime : Theme.line, lineWidth: on ? 3 : 1))
                .overlay(alignment: .topTrailing) { CheckDot(on: on).padding(8) }
                .overlay(alignment: .bottomLeading) {
                    if m.isVideo { Image(systemName: "play.fill").font(.system(size: 11)).padding(8).foregroundStyle(.white) }
                }
                .opacity(on ? 0.75 : 1)
                .onTapGesture { store.toggle(m.id) }
            Text(keep ? "suggested keep" : (m.folder as NSString).lastPathComponent)
                .font(.label(10)).foregroundStyle(keep ? Theme.lime : Theme.dim).lineLimit(1).frame(width: 128, alignment: .leading)
        }
    }
}
