import CoreLocation
import SwiftUI
import UpslopeCore

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var newTrail = ""
    @State private var locationStatus = LocationService.shared.authorization

    var body: some View {
        NavigationStack {
            Form {
                Section("Snark") {
                    Picker("Level", selection: Binding(get: { model.settings.snark }, set: { v in model.updateSettings { $0.snark = v } })) {
                        Text("Mild").tag(SnarkLevel.mild)
                        Text("Standard").tag(SnarkLevel.standard)
                        Text("Unhinged").tag(SnarkLevel.unhinged)
                    }
                    .pickerStyle(.segmented)
                    Text(Snark.line(for: model.nextHour, level: model.settings.snark))
                        .font(UFont.body(14))
                        .foregroundStyle(Theme.muted)
                }

                Section {
                    ForEach(model.settings.watchList, id: \.self) { name in Text(name) }
                        .onDelete { idx in model.updateSettings { $0.watchList.remove(atOffsets: idx) } }
                    HStack {
                        TextField("Add a trail or lift", text: $newTrail)
                            .textInputAutocapitalization(.words)
                            .submitLabel(.done)
                            .onSubmit(add)
                        Button("Add", action: add).disabled(newTrail.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                } header: {
                    Text("Your trails")
                } footer: {
                    Text("Names must match stowe.com. You'll get a silent alert when one opens.")
                }

                Section {
                    LabeledContent("Location", value: locationText)
                    if locationStatus == .notDetermined {
                        Button("Allow location") { LocationService.shared.requestWhenInUse() }
                    } else if locationStatus == .authorizedWhenInUse {
                        Button("Allow \"Always\" so alerts follow you") { LocationService.shared.requestAlways() }
                    } else if locationStatus == .denied || locationStatus == .restricted {
                        Button("Open iPhone Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                        }
                    }
                } header: {
                    Text("Permissions")
                } footer: {
                    Text("Alerts are always silent. Upslope never asks for sound permission.")
                }

                Section("Data") {
                    LabeledContent("Next hour", value: AppConfig.pirateKey == nil ? "Open-Meteo (15 min)" : "Pirate Weather (1 min)")
                    LabeledContent("7-day + Mansfield", value: "Open-Meteo")
                    LabeledContent("Forecaster's take", value: "NWS Burlington")
                    LabeledContent("Resort report", value: "stowe.com")
                    LabeledContent("Radar", value: "NEXRAD via Iowa State")
                }

                Section {
                    NavigationLink("Diagnostics") { DiagnosticsView() }
                    LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .navigationTitle("Settings")
            .onAppear { locationStatus = LocationService.shared.authorization }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                locationStatus = LocationService.shared.authorization
            }
        }
    }

    var locationText: String {
        switch locationStatus {
        case .authorizedAlways: return "Always"
        case .authorizedWhenInUse: return "While using"
        case .denied: return "Off"
        case .restricted: return "Restricted"
        default: return "Not asked"
        }
    }

    func add() {
        let name = newTrail.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !model.settings.watchList.contains(name) else { return }
        model.updateSettings { $0.watchList.append(name) }
        newTrail = ""
    }
}
