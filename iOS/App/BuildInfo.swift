import Foundation

/// Build metadata from the app Info.plist; unexpanded or missing values fall back.
enum BuildInfo {
    static var version: String { version(info: mainInfo) }
    static var build: String { build(info: mainInfo) }
    static var commit: String { commit(info: mainInfo) }
    /// `CFBundleShortVersionString (CFBundleVersion)`, e.g. `1.0.0 (261024.12345)`.
    static var displayVersion: String { displayVersion(info: mainInfo) }

    static func version(info: [String: Any]) -> String { value("CFBundleShortVersionString", in: info) ?? "dev" }
    static func build(info: [String: Any]) -> String { value("CFBundleVersion", in: info) ?? "dev" }
    static func commit(info: [String: Any]) -> String { value("GitCommit", in: info) ?? "unknown" }
    static func displayVersion(info: [String: Any]) -> String { "\(version(info: info)) (\(build(info: info)))" }

    private static var mainInfo: [String: Any] { Bundle.main.infoDictionary ?? [:] }

    private static func value(_ key: String, in info: [String: Any]) -> String? {
        guard let s = info[key] as? String, !s.isEmpty, !s.contains("$(") else { return nil }
        return s
    }
}
