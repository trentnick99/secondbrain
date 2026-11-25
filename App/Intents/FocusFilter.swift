import AppIntents
import WidgetKit

/// A Focus filter: in iOS Settings › Focus, choose a Focus (like Personal or Sleep) › Focus Filters ›
/// Second Brain › Off duty. While that Focus is on, widgets and Home stay quiet about work and the
/// shift Live Activity is removed. Nothing is deleted or rescheduled.
struct SecondBrainFocusFilter: SetFocusFilterIntent {
    static var title: LocalizedStringResource = "Second Brain"
    static var description: IntentDescription? = IntentDescription("Keep work out of sight while this Focus is on.")

    @Parameter(title: "Off duty", default: true)
    var offDuty: Bool

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: offDuty ? "Off duty: hide work" : "Show work")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        AppGroup.defaults.set(offDuty, forKey: SettingsKey.offDuty)
        WidgetCenter.shared.reloadAllTimelines()
        if offDuty {
            ShiftActivityController.endAll()
        } else {
            ShiftActivityController.refresh(in: PersistenceController.shared.mainContext)
        }
        return .result()
    }
}
