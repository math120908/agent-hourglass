import Foundation

/// App Group shared by the iOS app and its widget: container, defaults, keychain group.
enum AppGroup {
    static let id = "group.cc.kuoc.agent-hourglass"

    static var containerURL: URL {
        guard let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id) else {
            preconditionFailure("App Group \(id) missing from entitlements")
        }
        return url
    }

    static var defaults: UserDefaults {
        guard let defaults = UserDefaults(suiteName: id) else {
            preconditionFailure("App Group \(id) missing from entitlements")
        }
        return defaults
    }

    static let keychainAccessGroup: String = {
        let value = Bundle.main.object(forInfoDictionaryKey: "AHKeychainAccessGroup") as? String ?? ""
        precondition(!value.isEmpty && !value.contains("$("), "AHKeychainAccessGroup missing or unexpanded in Info.plist")
        return value
    }()
}
