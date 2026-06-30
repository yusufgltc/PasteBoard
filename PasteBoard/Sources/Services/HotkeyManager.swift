import Carbon

/// Registers and unregisters the global ⌘⇧V hotkey using the Carbon
/// `RegisterEventHotKey` API.
///
/// **Why Carbon?** `NSEvent.addGlobalMonitorForEvents(matching: .keyDown)` silently
/// stops firing on macOS 13+ unless the app has been granted Accessibility
/// permission. Carbon `RegisterEventHotKey` operates at the kernel event-handler
/// level and requires no additional entitlements.
final class HotkeyManager {

    /// Fired on the main queue each time ⌘⇧V is pressed.
    var onHotkey: (() -> Void)?

    private var hotKeyRef:  EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    /// Installs the Carbon event handler and registers the ⌘⇧V hotkey.
    /// Safe to call multiple times — subsequent calls have no effect if already started.
    func start() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind:  UInt32(kEventHotKeyPressed)
        )
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData -> OSStatus in
                guard let ptr = userData else { return OSStatus(noErr) }
                let mgr = Unmanaged<HotkeyManager>.fromOpaque(ptr).takeUnretainedValue()
                DispatchQueue.main.async { mgr.onHotkey?() }
                return OSStatus(noErr)
            },
            1, &eventType, selfPtr, &handlerRef
        )
        var hotkeyID = EventHotKeyID(signature: OSType(0x50424F41), id: 1) // 'PBOA'
        RegisterEventHotKey(
            UInt32(kVK_ANSI_V),
            UInt32(cmdKey | shiftKey),
            hotkeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }

    /// Unregisters the hotkey and removes the event handler.
    /// Should be called before the manager is deallocated.
    func stop() {
        if let hotKey  = hotKeyRef  { UnregisterEventHotKey(hotKey);  hotKeyRef  = nil }
        if let handler = handlerRef { RemoveEventHandler(handler);    handlerRef = nil }
    }
}
