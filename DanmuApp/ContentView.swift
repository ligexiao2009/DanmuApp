import SwiftUI

struct ContentView: View {
    @State private var selectedTab: Tab = .library

    enum Tab: String, CaseIterable {
        case library = "剧库"
        case video = "视频"
        case live = "直播"

        var icon: String {
            switch self {
            case .library: return "tv.fill"
            case .video: return "play.rectangle.fill"
            case .live: return "antenna.radiowaves.left.and.right"
            }
        }
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            LibraryView(onPlayEpisode: { folderPath, videoFile in
                UserDefaults.standard.set(folderPath, forKey: "lib_play_folder")
                UserDefaults.standard.set(videoFile, forKey: "lib_play_file")
                selectedTab = .video
            })
                .tabItem { Label(Tab.library.rawValue, systemImage: Tab.library.icon) }
                .tag(Tab.library)

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
