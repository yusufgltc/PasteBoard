import Foundation
import Combine

/// How long the clipboard history is retained before entries are purged.
///
/// Raw values are stored in `UserDefaults` so the selection survives app restarts.
enum RetentionOption: Int, CaseIterable, Identifiable {
    case thirtyMinutes = 0
    case eightHours    = 1
    case sevenDays     = 2

    var id: Int { rawValue }

    /// Human-readable label shown in the Settings picker.
    var label: String {
        switch self {
        case .thirtyMinutes: return "30 Minutes"
        case .eightHours:    return "8 Hours"
        case .sevenDays:     return "7 Days"
        }
    }

    /// The equivalent `TimeInterval` used by ``ClipboardStore`` when purging.
    var duration: TimeInterval {
        switch self {
        case .thirtyMinutes: return 30 * 60
        case .eightHours:    return 8  * 60 * 60
        case .sevenDays:     return 7  * 24 * 60 * 60
        }
    }
}

/// Singleton that owns all user-facing preferences and persists them in `UserDefaults`.
///
/// Conform to `ObservableObject` so SwiftUI views (``SettingsView``) can react to
/// changes. Other non-SwiftUI components (``ClipboardStore``, ``PanelController``,
/// ``AppDelegate``) observe the published properties via Combine.
final class AppSettings: ObservableObject {

    /// The shared instance — use this everywhere instead of creating a new instance.
    static let shared = AppSettings()

    /// When `false` the monitor stops recording, the panel is hidden, and the
    /// status-bar "Show PasteBoard" item is grayed out.
    @Published var isMonitoringEnabled: Bool {
        didSet { defaults.set(isMonitoringEnabled, forKey: Keys.monitoring) }
    }

    /// Controls how far back the history is kept. Changing this immediately
    /// triggers a purge in ``ClipboardStore``.
    @Published var retentionOption: RetentionOption {
        didSet { defaults.set(retentionOption.rawValue, forKey: Keys.retention) }
    }

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let monitoring = "pasteboardMonitoringEnabled"
        static let retention  = "pasteboardRetentionOption"
    }

    private init() {
        let monRaw = defaults.object(forKey: Keys.monitoring) as? Bool ?? true
        let retRaw = defaults.object(forKey: Keys.retention)  as? Int  ?? RetentionOption.eightHours.rawValue
        isMonitoringEnabled = monRaw
        retentionOption     = RetentionOption(rawValue: retRaw) ?? .eightHours
    }
}
