import Foundation

/// What the app should do with its one silent next-hour alert.
public enum AlertAction: Equatable, Sendable {
    case none
    /// Post a new alert.
    case post(AlertContent)
    /// Replace the delivered alert that has the same id.
    case replace(AlertContent)
    /// Remove a delivered alert that is out of date.
    case remove(id: String)
}

public struct AlertContent: Equatable, Sendable {
    public var id: String
    public var title: String
    public var body: String
}

/// Persisted between runs so we alert once per event.
public struct AlertState: Codable, Equatable, Sendable {
    public var activeID: String?
    public var postedStart: Date?
    public var postedEnd: Date?
    public var postedType: PrecipType?

    public init() {}
}

/// Rules from PLAN.md §3: one alert per event, replaced (not repeated) when the
/// start moves more than 5 minutes or the type changes; a new event needs 30+ dry minutes.
public enum AlertPlanner {
    public static let shiftMinutes = 5.0
    public static let newEventDryMinutes = 30.0

    public static func plan(state: AlertState, next: NextHourState, now: Date, snark: SnarkLevel) -> (AlertAction, AlertState) {
        var s = state
        let dryGap = newEventDryMinutes * 60

        guard let event = next.event else {
            // Dry. Retire the active alert once it has been dry long enough.
            if let id = s.activeID, let end = s.postedEnd, now.timeIntervalSince(end) >= dryGap {
                return (.remove(id: id), AlertState())
            }
            return (.none, s)
        }

        let title = NextHourText.alertTitle(next) ?? event.type.noun
        let body = Snark.line(for: next, level: snark)

        let isNewEvent: Bool = {
            guard s.activeID != nil, let end = s.postedEnd else { return true }
            return event.start.timeIntervalSince(end) >= dryGap
        }()

        if isNewEvent {
            let id = "upslope.nexthour.\(Int(event.start.timeIntervalSince1970))"
            s.activeID = id
            s.postedStart = event.start
            s.postedEnd = event.end
            s.postedType = event.type
            return (.post(AlertContent(id: id, title: title, body: body)), s)
        }

        let id = s.activeID!
        s.postedEnd = max(s.postedEnd ?? event.end, event.end)
        let isOngoing: Bool = { if case .ongoing = next { return true } else { return false } }()
        let shifted = s.postedStart.map { abs(event.start.timeIntervalSince($0)) > shiftMinutes * 60 } ?? true
        let retyped = s.postedType != event.type
        // Once it's falling, a moving "start" is just the forecast catching up, so ignore it.
        if retyped || (shifted && !isOngoing) {
            s.postedStart = event.start
            s.postedType = event.type
            return (.replace(AlertContent(id: id, title: title, body: body)), s)
        }
        return (.none, s)
    }
}
