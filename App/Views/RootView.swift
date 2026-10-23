import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            Tab("Now", systemImage: "clock") { NowView() }
            Tab("Radar", systemImage: "dot.radiowaves.left.and.right") { RadarView() }
            Tab("Mansfield", systemImage: "mountain.2") { MansfieldView() }
            Tab("Settings", systemImage: "slider.horizontal.3") { SettingsView() }
        }
        .tint(Theme.accent)
        .background(Theme.bg)
    }
}
