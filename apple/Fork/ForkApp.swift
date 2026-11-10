import SwiftUI
import Observation

enum Section: String, CaseIterable, Identifiable {
    case today = "Today", boards = "Boards", map = "Map", library = "Library", history = "History", settings = "Settings"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .today: "square.stack"
        case .boards: "rectangle.3.group"
        case .map: "point.3.connected.trianglepath.dotted"
        case .library: "square.grid.2x2"
        case .history: "clock"
        case .settings: "gear"
        }
    }
}
@MainActor @Observable final class AppNavigation {
    var selection: Section = .today
    var mapFocus: String?
    func focus(_ idea: String) { mapFocus = idea; selection = .map }
}
@main struct ForkApp: App {
    @State private var api = APIClient()
    @State private var navigation = AppNavigation()
    var body: some SwiftUI.Scene {
        WindowGroup {
            RootView().environment(api).environment(navigation)
                #if os(macOS)
                .frame(minWidth: 1000, minHeight: 700)
                #endif
        }
        #if os(macOS)
        .defaultSize(width: 1100, height: 800)
        #endif
    }
}
struct RootView: View {
    @Environment(APIClient.self) private var api
    @Environment(AppNavigation.self) private var navigation
    var body: some View {
        @Bindable var navigation = navigation
        Group {
            #if os(iOS)
            TabView(selection: $navigation.selection) {
                ForEach(Section.allCases) { section in
                    Tab(section.rawValue, systemImage: section.symbol, value: section) {
                        NavigationStack { screen(section) }
                    }
                }
            }
            #else
            NavigationSplitView {
                List(Section.allCases, selection: Binding<Section?>(get: { navigation.selection }, set: { if let value = $0 { navigation.selection = value } })) { section in
                    Label(section.rawValue, systemImage: section.symbol).tag(section)
                }.navigationTitle("Fork")
            } detail: {
                NavigationStack { screen(navigation.selection) }
            }
            #endif
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if api.unauthorized {
                Button { navigation.selection = .settings } label: {
                    Label("Check token in Settings", systemImage: "key").frame(maxWidth: .infinity).padding(8)
                }.buttonStyle(.bordered).tint(.orange)
            }
        }
    }
    @ViewBuilder private func screen(_ section: Section) -> some View {
        switch section {
        case .today: TodayView()
        case .boards: BoardsView()
        case .map: MapView()
        case .library: LibraryView()
        case .history: HistoryView()
        case .settings: SettingsView()
        }
    }
}
