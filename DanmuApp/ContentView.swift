import SwiftUI

struct ContentView: View {
    @State private var selectedTab: Tab = .home

    enum Tab: String, CaseIterable {
        case home = "首页"
        case live = "直播"
        case video = "视频"

        var icon: String {
            switch self {
            case .home: return "house.fill"
            case .live: return "antenna.radiowaves.left.and.right"
            case .video: return "play.rectangle.fill"
            }
        }
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView(selectedTab: $selectedTab)
                .tabItem { Label(Tab.home.rawValue, systemImage: Tab.home.icon) }
                .tag(Tab.home)

            VideoView()
                .tabItem { Label(Tab.video.rawValue, systemImage: Tab.video.icon) }
                .tag(Tab.video)

            LiveView()
                .tabItem { Label(Tab.live.rawValue, systemImage: Tab.live.icon) }
                .tag(Tab.live)
        }
        .tint(.indigo)
    }
}
