import SwiftUI

@main
struct SiftApp: App {
    var body: some Scene {
        let w = WindowGroup { RootView().preferredColorScheme(.dark) }
        #if os(macOS)
        w.defaultSize(width: 1040, height: 780)
        #else
        w
        #endif
    }
}

enum SiftTab: String, CaseIterable, Identifiable {
    case overview = "Overview", duplicates = "Duplicates", folders = "Folders", caches = "Caches"
    var id: String { rawValue }
    static var available: [SiftTab] {
        #if os(macOS)
        return allCases
        #else
        return [.overview, .duplicates]
        #endif
    }
}

struct TabBar: View {
    @Binding var tab: SiftTab
    var body: some View {
        HStack(spacing: 4) {
            ForEach(SiftTab.available) { t in
                Button { withAnimation(.spring(duration: 0.3)) { tab = t } } label: {
                    Text(t.rawValue).font(.label(13))
                        .foregroundStyle(tab == t ? Color.black.opacity(0.85) : Theme.dim)
                        .padding(.horizontal, 16).padding(.vertical, 9)
                        .background(Capsule().fill(tab == t ? AnyShapeStyle(Theme.lime) : AnyShapeStyle(Color.clear)))
                }.buttonStyle(.plain)
            }
        }
        .padding(5)
        .background(Capsule().fill(.ultraThinMaterial))
        .background(Capsule().fill(Theme.card.opacity(0.8)))
        .overlay(Capsule().stroke(Theme.line, lineWidth: 1))
    }
}
