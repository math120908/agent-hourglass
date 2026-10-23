import Foundation

/// Build metadata from the app Info.plist; unexpanded or missing values fall back.
enum BuildInfo {
    static var version: String { value("CFBundleShortVersionString") ?? "dev" }
    static var build: String { value("CFBundleVersion") ?? "dev" }
    static var commit: String { value("GitCommit") ?? "unknown" }

    private static func value(_ key: String) -> String? {
        guard let s = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              !s.isEmpty, !s.contains("$(")
        else { return nil }
        return s
    }
}
