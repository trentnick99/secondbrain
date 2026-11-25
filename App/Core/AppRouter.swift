import Foundation
import Observation
import SwiftUI
import SecondBrainCore

enum AppTab: String, Hashable, CaseIterable {
    case home, tasks, matrix, associates, notes

    var title: String {
        switch self {
        case .home: return "Home"
        case .tasks: return "Tasks"
        case .matrix: return "Matrix"
        case .associates: return "Associates"
        case .notes: return "Notes"
        }
    }

    var systemImage: String {
        switch self {
        case .home: return "house"
        case .tasks: return "checklist"
        case .matrix: return "square.grid.2x2"
        case .associates: return "person.2"
        case .notes: return "note.text"
        }
    }
}

enum Route: Equatable {
    case tab(AppTab)
    case capture(CaptureKind?)
    case task(UUID)
    case shift
    case planner
    case weeklyReview
    case settings
    case overdue
    case storeTerms(String?)
    case seasonPlanner
    case role
    case routines
    case importNotes(String?, mode: ImportMode = .paste)
    case standards(String?)
    case floorWalk
    case huddle
    case timeline
}

/// Wraps an id so it can drive `.sheet(item:)`.
struct TaskRef: Identifiable, Hashable {
    let id: UUID
}

/// App-wide navigation state: selected tab, sheets, and a transient confirmation toast.
@MainActor
@Observable
final class AppRouter {
    static let shared = AppRouter()

    var selectedTab: AppTab = .home
    var showCapture = false
    var captureKind: CaptureKind?
    /// Text to pre-fill in Quick Capture (from a `secondbrain://capture?text=` link). Never saved automatically.
    var captureText: String?
    var presentedTask: TaskRef?
    var showEndShift = false
    var showPlanner = false
    var showWeeklyReview = false
    var showSettings = false
    var showStoreTerms = false
    var showSeasonPlanner = false
    var showRole = false
    var showRoutines = false
    var showImport = false
    var importText: String?
    var importMode: ImportMode = .paste
    var showStandards = false
    var showFloorWalk = false
    var showHuddle = false
    var showTimeline = false
    var standardsQuery: String?
    var storeTermsQuery: String?
    var taskFilterRequest: TaskFilter?
    var toast: String?
    private var toastTask: Task<Void, Never>?

    func open(_ route: Route) {
        switch route {
        case .tab(let tab):
            dismissSheets()
            selectedTab = tab
        case .capture(let kind):
            presentedTask = nil
            captureKind = kind
            captureText = nil
            showCapture = true
        case .task(let id):
            showCapture = false
            presentedTask = TaskRef(id: id)
        case .shift:
            dismissSheets()
            showEndShift = true
        case .planner:
            dismissSheets()
            showPlanner = true
        case .weeklyReview:
            dismissSheets()
            showWeeklyReview = true
        case .settings:
            dismissSheets()
            showSettings = true
        case .overdue:
            dismissSheets()
            selectedTab = .tasks
            taskFilterRequest = .overdue
        case .storeTerms(let query):
            dismissSheets()
            storeTermsQuery = query
            showStoreTerms = true
        case .seasonPlanner:
            dismissSheets()
            showSeasonPlanner = true
        case .role:
            dismissSheets()
            showRole = true
        case .routines:
            dismissSheets()
            showRoutines = true
        case .importNotes(let text, let mode):
            dismissSheets()
            importText = text
            importMode = mode
            showImport = true
        case .standards(let query):
            dismissSheets()
            standardsQuery = query
            showStandards = true
        case .floorWalk:
            dismissSheets()
            showFloorWalk = true
        case .huddle:
            dismissSheets()
            showHuddle = true
        case .timeline:
            dismissSheets()
            showTimeline = true
        }
    }

    func open(url: URL) {
        guard url.scheme == DeepLink.scheme else { return }
        let host = url.host ?? ""
        let parts = url.pathComponents.filter { $0 != "/" }
        switch host {
        case "capture":
            open(.capture(nil))
            captureText = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first { $0.name == "text" }?.value
        case "review": open(.weeklyReview)
        case "settings": open(.settings)
        case "home": open(.tab(.home))
        case "tasks": open(.tab(.tasks))
        case "matrix": open(.tab(.matrix))
        case "associates": open(.tab(.associates))
        case "notes": open(.tab(.notes))
        case "shift": open(.shift)
        case "planner": open(.planner)
        case "overdue": open(.overdue)
        case "season": open(.seasonPlanner)
        case "role": open(.role)
        case "routines": open(.routines)
        case "import":
            open(.importNotes(URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first { $0.name == "text" }?.value))
        case "walknotes":
            open(.importNotes(nil, mode: .speak))
        case "walk":
            open(.floorWalk)
        case "huddle":
            open(.huddle)
        case "timeline":
            open(.timeline)
        case "standards", "ask":
            open(.standards(URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first { $0.name == "q" }?.value))
        case "terms":
            let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first { $0.name == "q" }?.value
            open(.storeTerms(query))
        case "task":
            if let first = parts.first, let id = UUID(uuidString: first) { open(.task(id)) }
        default: open(.tab(.home))
        }
    }

    private func dismissSheets() {
        showCapture = false
        presentedTask = nil
        showEndShift = false
        showPlanner = false
        showWeeklyReview = false
        showSettings = false
        showStoreTerms = false
        showSeasonPlanner = false
        showRole = false
        showRoutines = false
        showImport = false
        showStandards = false
        showFloorWalk = false
        showHuddle = false
        showTimeline = false
    }

    func showToast(_ message: String) {
        toastTask?.cancel()
        withAnimation(.snappy) { toast = message }
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_400_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut) { self?.toast = nil }
        }
    }
}
