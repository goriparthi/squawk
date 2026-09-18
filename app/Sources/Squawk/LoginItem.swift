import Foundation
import ServiceManagement

/// Open at login via SMAppService. No helper bundle and no privileged install:
/// the app registers itself, and macOS lists it in System Settings under
/// General, Login Items, where it can be revoked independently of Squawk.
@MainActor
enum LoginItem {
    /// Approval pending counts as on. macOS has the registration; it is waiting
    /// for the user in System Settings. Reporting that as off made the menu row
    /// never stick: clicking it just registered again, and it still read as off.
    static var isEnabled: Bool {
        switch SMAppService.mainApp.status {
        case .enabled, .requiresApproval: true
        default: false
        }
    }

    /// On, but not yet honoured by macOS, which the menu shows differently so
    /// the state is not silently wrong.
    static var awaitingApproval: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }

    static var isAvailable: Bool {
        SMAppService.mainApp.status != .notFound
    }

    /// What macOS currently thinks, which is not always what was asked for: the
    /// user can turn it off in System Settings, and a build running from outside
    /// Applications is refused outright.
    static var statusDescription: String {
        switch SMAppService.mainApp.status {
        case .enabled: "Squawk opens at login."
        case .notRegistered: "Squawk does not open at login."
        case .requiresApproval: "Waiting for approval in System Settings, Login Items."
        case .notFound: "Not available: move Squawk to Applications first."
        @unknown default: "Unknown login item state."
        }
    }

    /// Returns nil on success, or a message to show the user.
    @discardableResult
    static func set(_ enabled: Bool) -> String? {
        do {
            if enabled {
                guard SMAppService.mainApp.status != .enabled else { return nil }
                try SMAppService.mainApp.register()
                if SMAppService.mainApp.status == .requiresApproval {
                    return "Approve Squawk in System Settings, General, Login Items."
                }
                return nil
            }
            guard SMAppService.mainApp.status != .notRegistered else { return nil }
            try SMAppService.mainApp.unregister()
            return nil
        } catch {
            return "Could not change the login item: \(error.localizedDescription)"
        }
    }
}
