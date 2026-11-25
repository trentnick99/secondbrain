import SwiftData
import SwiftUI
import SecondBrainCore

struct RootView: View {
    @Environment(AppRouter.self) private var router
    @Environment(AppLock.self) private var lock
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(SettingsKey.hasCompletedOnboarding, store: AppGroup.defaults) private var hasCompletedOnboarding = false
    @AppStorage(SettingsKey.appearance, store: AppGroup.defaults) private var appearance = SettingsDefault.appearance
    @AppStorage(SettingsKey.appLockEnabled, store: AppGroup.defaults) private var appLockEnabled = false

    var body: some View {
        @Bindable var router = router

        TabView(selection: $router.selectedTab) {
            Tab(AppTab.home.title, systemImage: AppTab.home.systemImage, value: AppTab.home) {
                DashboardView()
            }
            Tab(AppTab.tasks.title, systemImage: AppTab.tasks.systemImage, value: AppTab.tasks) {
                TaskListView().withCaptureButton()
            }
            Tab(AppTab.matrix.title, systemImage: AppTab.matrix.systemImage, value: AppTab.matrix) {
                MatrixView()
            }
            Tab(AppTab.associates.title, systemImage: AppTab.associates.systemImage, value: AppTab.associates) {
                AssociatesView()
            }
            Tab(AppTab.notes.title, systemImage: AppTab.notes.systemImage, value: AppTab.notes) {
                NotesListView().withCaptureButton(kind: .note)
            }
        }
        .tint(Theme.accent)
        .preferredColorScheme(colorScheme)
        .sheet(item: $router.sheet) { sheet in
            sheetContent(sheet)
        }
        .fullScreenCover(isPresented: Binding(get: { !hasCompletedOnboarding }, set: { hasCompletedOnboarding = !$0 })) {
            OnboardingView()
        }
        .overlay(alignment: .top) { StoreWarningBanner() }
        .overlay(alignment: .bottom) { ToastView(message: router.toast) }
        .overlay {
            if lock.isLocked {
                LockScreenView().transition(.opacity)
            } else if appLockEnabled && scenePhase != .active {
                PrivacyShield()
            }
        }
    }

    @ViewBuilder
    private func sheetContent(_ sheet: ActiveSheet) -> some View {
        switch sheet {
        case .capture:
            QuickCaptureView(initialKind: router.captureKind, initialText: router.captureText)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        case .task(let id): TaskSheet(taskID: id)
        case .endShift: EndShiftView()
        case .planner: PlannerContainerView()
        case .weeklyReview: WeeklyReviewView()
        case .settings: SettingsView()
        case .storeTerms: StoreTermsView(initialQuery: router.storeTermsQuery)
        case .seasonPlanner: SeasonPlannerView()
        case .role: RoleSheet()
        case .routines:
            NavigationStack {
                RoutinesView().toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { router.dismissSheet() } } }
            }
        case .importNotes: ImportNotesView(initialText: router.importText, mode: router.importMode)
        case .standards: StandardsView(initialQuery: router.standardsQuery)
        case .floorWalk: FloorWalkView()
        case .huddle: HuddleView()
        case .timeline: ShiftTimelineView()
        }
    }

    private var colorScheme: ColorScheme? {
        switch AppearanceMode(rawValue: appearance) ?? .dark {
        case .system: return nil
        case .dark: return .dark
        case .light: return .light
        }
    }
}

/// Loads a task by id for presentation from notifications, widgets and Siri.
struct TaskSheet: View {
    let taskID: UUID
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            if let task = TaskActions.task(with: taskID, in: context) {
                TaskDetailView(task: task)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                    }
            } else {
                ContentUnavailableView("Task not found", systemImage: "questionmark.circle",
                                       description: Text("It may have been deleted."))
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                    }
            }
        }
    }
}

// MARK: - Quick Capture button (on every main screen)

/// The + button on Tasks and Notes. Home has its own Capture tile, so it isn't repeated there.
/// Lists get bottom room so their last row can scroll clear of the button.
struct CaptureButtonModifier: ViewModifier {
    var kind: CaptureKind?
    @Environment(AppRouter.self) private var router

    func body(content: Content) -> some View {
        content
            .contentMargins(.bottom, 84, for: .scrollContent)
            .overlay(alignment: .bottomTrailing) {
            Button {
                router.open(.capture(kind))
            } label: {
                Image(systemName: "plus")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.black)
                    .frame(width: 60, height: 60)
                    .background(Theme.accent, in: Circle())
                    .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
            }
            .padding(.trailing, 20)
            .padding(.bottom, 16)
            .accessibilityLabel("Quick Capture")
            .accessibilityHint("Capture a task, follow-up, note or reminder")
            .accessibilityIdentifier("quickCaptureButton")
            .sensoryFeedback(.impact(weight: .medium), trigger: router.sheet == .capture)
        }
    }
}

extension View {
    func withCaptureButton(kind: CaptureKind? = nil) -> some View { modifier(CaptureButtonModifier(kind: kind)) }
}

// MARK: - Overlays

struct ToastView: View {
    let message: String?

    var body: some View {
        if let message {
            Label(message, systemImage: "checkmark.circle.fill")
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(.thinMaterial, in: Capsule())
                .padding(.bottom, 96)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .accessibilityAddTraits(.isStaticText)
        }
    }
}

struct StoreWarningBanner: View {
    var body: some View {
        switch PersistenceController.state {
        case .normal:
            EmptyView()
        case .localFallback(let message), .temporary(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.footnote.weight(.medium))
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.warning.opacity(0.9))
                .foregroundStyle(.black)
        }
    }
}

struct PrivacyShield: View {
    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            Image(systemName: "lock.fill").font(.largeTitle).foregroundStyle(.secondary)
        }
        .ignoresSafeArea()
    }
}

struct LockScreenView: View {
    @Environment(AppLock.self) private var lock

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: 20) {
                Image(systemName: "sparkles")
                    .font(.system(size: 56))
                    .foregroundStyle(Theme.accent)
                Text("Coach Spark is locked")
                    .font(.title2.weight(.semibold))
                if let error = lock.lastError {
                    Text(error).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                Button {
                    Task { await lock.unlock() }
                } label: {
                    Label("Unlock with \(lock.biometryName)", systemImage: "faceid")
                        .frame(maxWidth: 280)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding()
        }
        .task { await lock.unlock() }
    }
}
