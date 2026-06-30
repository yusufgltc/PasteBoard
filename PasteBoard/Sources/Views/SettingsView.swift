import SwiftUI

/// Settings panel UI, embedded in a floating ``SettingsController`` window.
///
/// Three sections:
/// 1. **Monitoring toggle** — master on/off switch. Turning it off auto-clears
///    history and disables the other two sections.
/// 2. **Clipboard History Duration** — how long items are retained before purging.
/// 3. **Clear Clipboard History** — destructive button, disabled when monitoring is off.
struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    /// Injected by ``SettingsController``; calls ``ClipboardStore/clearAll()``.
    var onClearHistory: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {

            // Monitoring toggle
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Enable Clipboard Monitoring", isOn: $settings.isMonitoringEnabled)
                        .toggleStyle(.switch)
                    Text("Allow PasteBoard to track items you copy to the clipboard. Personal and sensitive information may appear in history.")
                        .font(.callout)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(4)
            }
            // Auto-clear history immediately when monitoring is turned off
            .onChange(of: settings.isMonitoringEnabled) { _, enabled in
                if !enabled { onClearHistory() }
            }

            // Retention — disabled (and grayed) when monitoring is off
            GroupBox("Clipboard History Duration") {
                Picker("", selection: $settings.retentionOption) {
                    ForEach(RetentionOption.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
                .padding(4)
            }
            .disabled(!settings.isMonitoringEnabled)

            // Clear history — also disabled when monitoring is off
            GroupBox {
                HStack {
                    Button(role: .destructive) {
                        onClearHistory()
                    } label: {
                        Label("Clear Clipboard History", systemImage: "trash")
                    }
                    Spacer()
                }
                .padding(4)
            }
            .disabled(!settings.isMonitoringEnabled)
        }
        .padding(20)
        .frame(width: 380)
    }
}
