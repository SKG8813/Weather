import AppIntents
import WidgetKit

enum PlaceOption: String, AppEnum {
    case here, stowe

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Location"
    static var caseDisplayRepresentations: [PlaceOption: DisplayRepresentation] = [
        .here: "Current location",
        .stowe: "Stowe"
    ]

    var choice: PlaceChoice { self == .here ? .here : .stowe }
}

/// Widget configuration: which place the widget shows.
struct PlaceIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Location"
    static var description = IntentDescription("Show the next hour for your current location or Stowe.")

    @Parameter(title: "Location", default: .here)
    var place: PlaceOption

    init() {}
    init(place: PlaceOption) { self.place = place }
}
