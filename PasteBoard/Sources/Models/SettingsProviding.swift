import Combine

/// Read-only view of user preferences needed by non-UI components.
///
/// Conformance by ``AppSettings`` lets ``ClipboardStore``, ``PasteboardMonitor``,
/// and ``PanelController`` depend on this protocol rather than the concrete singleton,
/// which makes them independently testable.
protocol SettingsProviding: AnyObject {
    var isMonitoringEnabled: Bool { get }
    var retentionOption: RetentionOption { get }
    /// Emits the new `RetentionOption` each time the user changes it.
    var retentionOptionPublisher: AnyPublisher<RetentionOption, Never> { get }
}

extension AppSettings: SettingsProviding {
    var retentionOptionPublisher: AnyPublisher<RetentionOption, Never> {
        $retentionOption.eraseToAnyPublisher()
    }
}
