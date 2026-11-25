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

/// The one sheet on screen. Exactly one can be open, so a new route replaces whatever was showing
/// instead of two sheets fighting over the screen.
enum ActiveSheet: Identifiable, Equatable {
    case capture, task(UUID), endShift, planner, weeklyReview, settings, storeTerms, seasonPlanner, role, routines,
         importNotes, standards, floorWalk, huddle, timeline

    var id: String {
        if case .task(let id) = self { return "task-" + id.uuidString }
        return String(describing: self)
    }
}

/// App-wide navigation state: selected tab, the open sheet, and a transient confirmation toast.
@MainActor
@Observable
final class AppRouter {
    static let shared = AppRouter()

    var selectedTab: AppTab = .home
    var sheet: ActiveSheet?
    var captureKind: CaptureKind?
    /// Text to pre-fill in Quick Capture (from a `secondbrain://capture?text=` link). Never saved automatically.
    var captureText: String?
    var importText: String?
    var importMode: ImportMode = .paste
    var standardsQuery: String?
    var storeTermsQuery: String?
    var taskFilterRequest: TaskFilter?
    var toast: String?
    private var toastTask: Task<Void, Never>?

    func open(_ route: Route) {
        switch route {
        case .tab(let tab):
            sheet = nil
            selectedTab = tab
        case .capture(let kind):
            captureKind = kind
            captureText = nil
            sheet = .capture
        case .task(let id):
            sheet = .task(id)
        case .shift:
            sheet = .endShift
        case .planner:
            sheet = .planner
        case .weeklyReview:
            sheet = .weeklyReview
        case .settings:
            sheet = .settings
        case .overdue:
            sheet = nil
            selectedTab = .tasks
            taskFilterRequest = .overdue
        case .storeTerms(let query):
            storeTermsQuery = query
            sheet = .storeTerms
        case .seasonPlanner:
            sheet = .seasonPlanner
        case .role:
            sheet = .role
        case .routines:
            sheet = .routines
        case .importNotes(let text, let mode):
            importText = text
            importMode = mode
            sheet = .importNotes
        case .standards(let query):
            standardsQuery = query
            sheet = .standards
        case .floorWalk:
            sheet = .floorWalk
        case .huddle:
            sheet = .huddle
        case .timeline:
            sheet = .timeline
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

    func dismissSheet() { sheet = nil }

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
