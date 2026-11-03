import CoreLocation
import SwiftUI
import UpslopeCore

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var newTrail = ""
    @State private var pirateKey = Store.defaults.string(forKey: Store.pirateKeyKey) ?? ""
    @State private var locationStatus: CLAuthorizationStatus = .notDetermined
    @State private var keyCheck: KeyCheck = .idle
    @FocusState private var keyFieldFocused: Bool

    /// What happened the last time "Save key" was tapped.
    enum KeyCheck: Equatable {
        case idle, checking, removed
        case working(String)
        case failed(String)
    }

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

                Section {
                    SecureField("Paste your key", text: $pirateKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($keyFieldFocused)
                        .onSubmit(savePirateKey)
                    Button(action: savePirateKey) {
                        HStack {
                            Text(keyCheck == .checking ? "Checking key…" : "Save key")
                            if keyCheck == .checking {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(keyCheck == .checking)
                    keyStatusRow
                } header: {
                    Text("Pirate Weather key")
                } footer: {
                    Text("Free from pirateweather.net. Used only when rain or snow is possible in the next 2 hours, so a free key goes a long way. Without it, Upslope uses 15-minute data.")
                }

                Section("Data") {
                    LabeledContent("Next hour", value: AppConfig.pirateKey == nil ? "Open-Meteo (15 min)" : "Pirate Weather when wet")
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

    /// Shows what's stored and whether Pirate Weather accepted it.
    @ViewBuilder var keyStatusRow: some View {
        switch keyCheck {
        case .idle:
            if let stored = Store.defaults.string(forKey: Store.pirateKeyKey), stored.count >= 4 {
                Label("Key saved (ends in \(stored.suffix(4)))", systemImage: "key.fill")
                    .foregroundStyle(Theme.muted)
            }
        case .checking:
            EmptyView()
        case .removed:
            Label("Key removed. Using Open-Meteo's 15-minute data.", systemImage: "minus.circle")
                .foregroundStyle(Theme.muted)
        case .working(let detail):
            Label(detail, systemImage: "checkmark.circle.fill")
                .foregroundStyle(Theme.trailGreen)
        case .failed(let detail):
            Label(detail, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.accent)
        }
    }

    func savePirateKey() {
        keyFieldFocused = false
        let key = pirateKey.trimmingCharacters(in: .whitespacesAndNewlines)
        pirateKey = key
        Store.defaults.set(key, forKey: Store.pirateKeyKey)
        let haptics = UINotificationFeedbackGenerator()

        guard !key.isEmpty else {
            keyCheck = .removed
            haptics.notificationOccurred(.success)
            Task { await model.refresh(force: true) }
            return
        }

        keyCheck = .checking
        Task {
            do {
                // One test call so you know right away whether the key works.
                let result = try await PirateWeatherClient(apiKey: key).fetch(Places.stowe)
                let minutes = result.nextHour?.points.count ?? 0
                keyCheck = .working("Saved and working. Got \(minutes) minutes of data for Stowe.")
                haptics.notificationOccurred(.success)
            } catch HTTPError.status(let code) where code == 401 || code == 403 {
                keyCheck = .failed("Saved, but Pirate Weather rejected this key. Check that you copied all of it.")
                haptics.notificationOccurred(.error)
            } catch HTTPError.status(429) {
                keyCheck = .failed("Saved, but this key is out of calls for now. Upslope will use Open-Meteo until it resets.")
                haptics.notificationOccurred(.warning)
            } catch {
                keyCheck = .failed("Saved, but couldn't reach Pirate Weather to check it. Try again when you have signal.")
                haptics.notificationOccurred(.warning)
            }
            await model.refresh(force: true)
        }
    }

    func add() {
        let name = newTrail.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !model.settings.watchList.contains(name) else { return }
        model.updateSettings { $0.watchList.append(name) }
        newTrail = ""
    }
}
