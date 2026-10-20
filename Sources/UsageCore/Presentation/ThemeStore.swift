import Foundation
import Observation

/// The chosen theme, persisted under `UserDefaults` key `theme`. External writes
/// (`defaults write <bundle> theme instrument`) are picked up live.
@MainActor @Observable
public final class ThemeStore {
    public static let key = "theme"
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var observer: KeyObserver?

    public var theme: Theme {
        didSet {
            guard theme != oldValue else { return }
            defaults.set(theme.rawValue, forKey: Self.key)
        }
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        theme = Theme(storedValue: defaults.string(forKey: Self.key))
        observer = KeyObserver(defaults: defaults, key: Self.key) { [weak self] in
            Task { @MainActor in self?.reload() }
        }
    }

    /// Re-reads the stored value; assigns only on change so observers fire once.
    public func reload() {
        let stored = Theme(storedValue: defaults.string(forKey: Self.key))
        if stored != theme { theme = stored }
    }
}

/// KVO on a `UserDefaults` key; unlike `didChangeNotification` it also fires for writes
/// from other processes (`defaults write`).
private final class KeyObserver: NSObject, @unchecked Sendable {
    private let defaults: UserDefaults
    private let key: String
    private let onChange: @Sendable () -> Void

    init(defaults: UserDefaults, key: String, onChange: @escaping @Sendable () -> Void) {
        self.defaults = defaults
        self.key = key
        self.onChange = onChange
        super.init()
        defaults.addObserver(self, forKeyPath: key, options: [.new], context: nil)
    }

    deinit { defaults.removeObserver(self, forKeyPath: key) }

    override func observeValue(
        forKeyPath keyPath: String?,
        of object: Any?,
        change: [NSKeyValueChangeKey: Any]?,
        context: UnsafeMutableRawPointer?
    ) {
        onChange()
    }
}
