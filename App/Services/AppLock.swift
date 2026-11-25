import Foundation
import LocalAuthentication
import Observation

/// Optional Face ID / passcode lock for the app.
@MainActor
@Observable
final class AppLock {
    static let shared = AppLock()

    private(set) var isLocked: Bool = false
    private(set) var lastError: String?
    private var isAuthenticating = false

    var biometryName: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return "Passcode"
        }
    }

    var canUseDeviceAuthentication: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    func lockIfEnabled() {
        guard AppSettings.appLockEnabled, !PersistenceController.isUITesting else { return }
        isLocked = true
    }

    func unlock() async {
        guard isLocked, !isAuthenticating else { return }
        isAuthenticating = true
        defer { isAuthenticating = false }
        let context = LAContext()
        context.localizedCancelTitle = "Cancel"
        do {
            let ok = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Unlock Coach Spark")
            if ok {
                isLocked = false
                lastError = nil
            }
        } catch {
            lastError = (error as? LAError)?.code == .userCancel ? nil : error.localizedDescription
        }
    }

    /// Confirms identity before turning the lock on, so nobody locks themselves out.
    func verifyForEnabling() async -> Bool {
        let context = LAContext()
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) else { return false }
        return (try? await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Turn on app lock")) ?? false
    }
}
