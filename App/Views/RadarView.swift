import MapKit
import SwiftUI
import UpslopeCore

/// NEXRAD composite tiles from the Iowa Environmental Mesonet (free, no key).
/// Ten past frames at 5-minute steps plus "now", animated by fading overlays.
struct RadarView: View {
    @Environment(AppModel.self) private var model
    @State private var frame = RadarFrames.layers.count - 1
    @State private var playing = true

    var body: some View {
        let here = Store.load(SavedLocation.self, .lastLocation)?.coordinate ?? Places.stowe
        ZStack(alignment: .bottom) {
            RadarMap(center: CLLocationCoordinate2D(latitude: here.latitude, longitude: here.longitude), frame: frame)
                .ignoresSafeArea(edges: .top)
            VStack(spacing: 8) {
                HStack {
                    Button {
                        playing.toggle()
                    } label: {
                        Image(systemName: playing ? "pause.fill" : "play.fill")
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel(playing ? "Pause" : "Play")
                    Slider(value: Binding(get: { Double(frame) }, set: { frame = Int($0); playing = false }),
                           in: 0...Double(RadarFrames.layers.count - 1), step: 1)
                    Text(RadarFrames.label(frame))
                        .font(UFont.body(14, weight: .semibold))
                        .frame(width: 64, alignment: .trailing)
                }
                Text("Radar: NWS NEXRAD via Iowa Environmental Mesonet")
                    .font(UFont.body(11))
                    .foregroundStyle(Theme.muted)
            }
            .tint(Theme.accent)
            .foregroundStyle(Theme.text)
            .padding(12)
            .background(Theme.bg.opacity(0.9), in: RoundedRectangle(cornerRadius: 16))
            .padding(12)
        }
        .task(id: playing) {
            while playing && !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(frame == RadarFrames.layers.count - 1 ? 1500 : 500))
                if playing { frame = (frame + 1) % RadarFrames.layers.count }
            }
        }
    }
}

enum RadarFrames {
    /// Oldest first; the last one is current.
    static let layers: [String] = stride(from: 50, through: 5, by: -5).map { String(format: "nexrad-n0q-900913-m%02dm", $0) } + ["nexrad-n0q-900913"]

    static func label(_ i: Int) -> String {
        let minutesAgo = (layers.count - 1 - i) * 5
        return minutesAgo == 0 ? "Now" : "-\(minutesAgo) min"
    }

    static func overlay(_ layer: String) -> MKTileOverlay {
        let o = MKTileOverlay(urlTemplate: "https://mesonet.agron.iastate.edu/cache/tile.py/1.0.0/\(layer)/{z}/{x}/{y}.png")
        o.canReplaceMapContent = false
        o.maximumZ = 12
        return o
    }
}

struct RadarMap: UIViewRepresentable {
    var center: CLLocationCoordinate2D
    var frame: Int

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.overrideUserInterfaceStyle = .dark
        map.pointOfInterestFilter = .excludingAll
        map.showsUserLocation = true
        map.setRegion(MKCoordinateRegion(center: center, latitudinalMeters: 400_000, longitudinalMeters: 400_000), animated: false)
        for layer in RadarFrames.layers {
            let o = RadarFrames.overlay(layer)
            context.coordinator.overlays.append(o)
            map.addOverlay(o, level: .aboveRoads)
        }
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        context.coordinator.show(frame)
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var overlays: [MKTileOverlay] = []
        var renderers: [ObjectIdentifier: MKTileOverlayRenderer] = [:]
        var current = RadarFrames.layers.count - 1

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let tile = overlay as? MKTileOverlay else { return MKOverlayRenderer(overlay: overlay) }
            let r = MKTileOverlayRenderer(tileOverlay: tile)
            r.alpha = overlays.firstIndex(where: { $0 === tile }) == current ? 0.75 : 0
            renderers[ObjectIdentifier(tile)] = r
            return r
        }

        func show(_ index: Int) {
            guard index != current else { return }
            current = index
            for (i, o) in overlays.enumerated() {
                renderers[ObjectIdentifier(o)]?.alpha = i == index ? 0.75 : 0
            }
        }
    }
}
