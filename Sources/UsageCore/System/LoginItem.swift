import Foundation
import Observation
import ServiceManagement

/// Login-item status, mirrored from `SMAppService.Status` (spec §10.5).
public enum LoginItemStatus: Sendable, Equatable {
    case notRegistered, enabled, requiresApproval, notFound
}

/// Seam over `SMAppService.mainApp` so tests never register for real.
@MainActor
public protocol LoginItemService: AnyObject {
    var status: LoginItemStatus { get }
    func register() throws
    func unregister() throws
}

@MainActor
public final class MainAppLoginService: LoginItemService {
    public init() {}

    public var status: LoginItemStatus {
        switch SMAppService.mainApp.status {
        case .enabled: .enabled
        case .requiresApproval: .requiresApproval
        case .notFound: .notFound
        default: .notRegistered
        }
    }

    public func register() throws { try SMAppService.mainApp.register() }
    public func unregister() throws { try SMAppService.mainApp.unregister() }

    public static func openSystemSettings() { SMAppService.openSystemSettingsLoginItems() }
}

/// "Launch at login" state. The toggle always reflects the live service status, never a cached `true`.
@MainActor
@Observable
public final class LoginItem {
    public private(set) var status: LoginItemStatus
    public private(set) var lastError: String?
    private let service: LoginItemService

    public init(service: LoginItemService) {
        self.service = service
        self.status = service.status
    }

    /// On means registered, including registered-but-awaiting-approval.
    public var isEnabled: Bool { status == .enabled || status == .requiresApproval }
    public var needsApproval: Bool { status == .requiresApproval }

    public func refresh() { status = service.status }

    /// Registration is tied to the bundle id: if the user last chose "on" but this bundle is not
    /// registered (e.g. after the id change), register again. Returns true when it re-registered.
    @discardableResult
    public func reconcile(defaults: UserDefaults = .standard) -> Bool {
        guard defaults.bool(forKey: LegacyMigration.launchAtLoginKey), status == .notRegistered else { return false }
        set(true)
        return true
    }

    public func set(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: LegacyMigration.launchAtLoginKey)
        do {
            if on { try service.register() } else { try service.unregister() }
            lastError = nil
        } catch {
            lastError = on ? "Couldn't turn on launch at login." : "Couldn't turn off launch at login."
        }
        refresh()
    }
}
