#if os(macOS)
import SwiftUI

struct RootView: View {
    @StateObject private var store = MacStore()
    @State private var tab: SiftTab = .overview

    var body: some View {
        ZStack(alignment: .top) {
            Theme.bg.ignoresSafeArea()
            RadialGradient(colors: [Theme.teal.opacity(0.18), .clear], center: .topTrailing, startRadius: 0, endRadius: 500).ignoresSafeArea()
            VStack(spacing: 0) {
                TabBar(tab: $tab).padding(.top, 14)
                Group {
                    switch tab {
                    case .overview: OverviewView(store: store, extra: AnyView(RootsCard(store: store)))
                    case .duplicates: DuplicatesView(store: store)
                    case .folders: FoldersView(store: store)
                    case .caches: CachesView(store: store)
                    }
                }
            }
        }
        .frame(minWidth: 900, minHeight: 680)
        .onChange(of: tab) { _, t in if t == .caches && store.caches.isEmpty { store.loadCaches() } }
    }
}

struct RootsCard: View {
    @ObservedObject var store: MacStore
    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Scan folders").font(.num(18)).foregroundStyle(Theme.ink)
                    Spacer()
                    Button("Add folder") { store.addRoot() }.buttonStyle(PillButtonStyle(filled: false))
                }
                FlowRow(store.roots) { u in
                    HStack(spacing: 6) {
                        Text(u.lastPathComponent).font(.label(12)).foregroundStyle(Theme.ink)
                        Button { store.removeRoot(u) } label: { Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.dim) }.buttonStyle(.plain)
                    }.padding(.horizontal, 12).padding(.vertical, 7).background(Capsule().fill(.white.opacity(0.1)))
                }
            }
        }
    }
}

struct FlowRow<T: Hashable, V: View>: View {
    let data: [T]; let content: (T) -> V
    init(_ data: [T], @ViewBuilder content: @escaping (T) -> V) { self.data = data; self.content = content }
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) { HStack(spacing: 8) { ForEach(data, id: \.self) { content($0) } } }
    }
}

struct FoldersView: View {
    @ObservedObject var store: MacStore
    @State private var mergeSheet = false
    @State private var target = ""

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    Text("Folders").font(.num(34)).foregroundStyle(Theme.ink)
                    Text(store.scanned ? "Select two or more to merge. Files move, nothing is deleted." : "Scan first to list folders")
                        .font(.label(14)).foregroundStyle(Theme.dim)
                    let maxB = max(store.folders.first?.bytes ?? 1, 1)
                    ForEach(store.folders) { f in
                        let on = store.selFolders.contains(f.id)
                        GlassCard(padding: 16) {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(spacing: 12) {
                                    CheckDot(on: on)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(f.name).font(.num(16)).foregroundStyle(Theme.ink).lineLimit(1)
                                        Text("\(f.count) files · \((f.path as NSString).abbreviatingWithTildeInPath)").font(.label(11)).foregroundStyle(Theme.dim).lineLimit(1)
                                    }
                                    Spacer()
                                    Text(readable(f.bytes)).font(.num(15)).foregroundStyle(Theme.ink)
                                }
                                GeometryReader { g in
                                    Capsule().fill(.white.opacity(0.08))
                                    Capsule().fill(on ? AnyShapeStyle(Theme.limeGradient) : AnyShapeStyle(Color.white.opacity(0.35)))
                                        .frame(width: max(g.size.width * CGFloat(f.bytes) / CGFloat(maxB), 6))
                                }.frame(height: 5)
                            }
                        }
                        .overlay(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).stroke(on ? Theme.lime : .clear, lineWidth: 2))
                        .onTapGesture { store.toggleFolder(f.id) }
                    }
                    Spacer().frame(height: 110)
                }
                .padding(24).frame(maxWidth: 860).frame(maxWidth: .infinity)
            }
            if store.selFolders.count >= 2 {
                ActionBar(title: "\(store.selFolders.count) folders", subtitle: "Merge into one", action: "Merge…", destructive: false) {
                    target = store.folders.filter { store.selFolders.contains($0.id) }.first?.path ?? ""
                    mergeSheet = true
                }.padding(.horizontal, 24).padding(.bottom, 18).frame(maxWidth: 860)
            }
        }
        .sheet(isPresented: $mergeSheet) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Merge into").font(.num(24))
                Picker("Target", selection: $target) {
                    ForEach(store.folders.filter { store.selFolders.contains($0.id) }) { f in Text("\(f.name) — \((f.path as NSString).abbreviatingWithTildeInPath)").tag(f.path) }
                }.labelsHidden().pickerStyle(.radioGroup)
                Text("Files from the other folders are moved here. Name clashes get a _1, _2 suffix.").font(.label(12)).foregroundStyle(Theme.dim)
                HStack { Spacer(); Button("Cancel") { mergeSheet = false }.buttonStyle(PillButtonStyle(filled: false)); Button("Merge") { mergeSheet = false; store.merge(into: target) }.buttonStyle(PillButtonStyle()) }
            }.padding(28).frame(width: 520).background(Theme.bg).preferredColorScheme(.dark)
        }
    }
}

struct CachesView: View {
    @ObservedObject var store: MacStore
    @State private var confirm = false
    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    Text("Caches").font(.num(34)).foregroundStyle(Theme.ink)
                    Text(store.loadingCaches ? "Measuring ~/Library/Caches…" : "\(store.caches.count) folders · \(readable(store.caches.reduce(0) { $0 + $1.size }))")
                        .font(.label(14)).foregroundStyle(Theme.dim)
                    if store.loadingCaches { ProgressView().tint(Theme.lime) }
                    let maxS = max(store.caches.first?.size ?? 1, 1)
                    ForEach(store.caches) { c in
                        let on = store.selCaches.contains(c.id)
                        GlassCard(padding: 16) {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(spacing: 12) {
                                    CheckDot(on: on)
                                    Text(c.name).font(.num(15)).foregroundStyle(Theme.ink).lineLimit(1)
                                    Spacer()
                                    Text(readable(c.size)).font(.num(15)).foregroundStyle(Theme.ink)
                                }
                                GeometryReader { g in
                                    Capsule().fill(.white.opacity(0.08))
                                    Capsule().fill(on ? AnyShapeStyle(Theme.limeGradient) : AnyShapeStyle(Color.white.opacity(0.35)))
                                        .frame(width: max(g.size.width * CGFloat(c.size) / CGFloat(maxS), 6))
                                }.frame(height: 5)
                            }
                        }
                        .overlay(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).stroke(on ? Theme.lime : .clear, lineWidth: 2))
                        .onTapGesture { store.toggleCache(c.id) }
                    }
                    if let m = store.message { Text(m).font(.label(13)).foregroundStyle(Theme.lime) }
                    Spacer().frame(height: 110)
                }
                .padding(24).frame(maxWidth: 860).frame(maxWidth: .infinity)
            }
            if !store.selCaches.isEmpty {
                ActionBar(title: "\(store.selCaches.count) selected", subtitle: readable(store.selCacheBytes), action: "Move to Trash") { confirm = true }
                    .padding(.horizontal, 24).padding(.bottom, 18).frame(maxWidth: 860)
            }
        }
        .confirmationDialog("Move \(store.selCaches.count) cache folders (\(readable(store.selCacheBytes))) to the Trash?", isPresented: $confirm, titleVisibility: .visible) {
            Button("Move to Trash", role: .destructive) { store.trashCaches() }
            Button("Cancel", role: .cancel) {}
        }
    }
}
#endif
