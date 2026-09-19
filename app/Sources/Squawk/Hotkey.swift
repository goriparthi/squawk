import AppKit
import Carbon.HIToolbox

/// A key combination that works while another app has focus.
///
/// Carbon's `RegisterEventHotKey` rather than an event monitor or a tap,
/// because those need Accessibility permission for something the system will
/// hand over for nothing. Asking to watch every keystroke in order to notice
/// one is not a trade worth offering anyone.
@MainActor
final class Hotkey {
    /// Held down and let go, which is what push to talk is.
    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?

    private var reference: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private static var live: [UInt32: Hotkey] = [:]
    private static var nextID: UInt32 = 1
    private var identifier: UInt32 = 0

    /// Option and space, which no application claims and one hand can reach.
    static let defaultKeyCode = UInt32(kVK_Space)
    static let defaultModifiers = UInt32(optionKey)

    var isRegistered: Bool { reference != nil }

    @discardableResult
    func register(keyCode: UInt32 = Hotkey.defaultKeyCode,
                  modifiers: UInt32 = Hotkey.defaultModifiers) -> Bool {
        unregister()
        identifier = Self.nextID
        Self.nextID += 1
        Self.live[identifier] = self

        let events = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                          eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                          eventKind: UInt32(kEventHotKeyReleased)),
        ]
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var identifier = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &identifier)
            let kind = GetEventKind(event)
            // Hopped to the main actor: the Carbon handler runs on the main
            // thread already, but the compiler cannot know that.
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let hotkey = Hotkey.live[identifier.id] else { return }
                    kind == UInt32(kEventHotKeyPressed) ? hotkey.onPress?() : hotkey.onRelease?()
                }
            }
            return noErr
        }, events.count, events, nil, &handler)

        let hotKeyID = EventHotKeyID(signature: OSType(0x53_51_57_4B), id: identifier)
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID,
                                         GetApplicationEventTarget(), 0, &reference)
        guard status == noErr else {
            // Something else owns the combination; the menu item still works.
            Self.live[identifier] = nil
            reference = nil
            return false
        }
        return true
    }

    func unregister() {
        if let reference { UnregisterEventHotKey(reference) }
        reference = nil
        if let handler { RemoveEventHandler(handler) }
        handler = nil
        Self.live[identifier] = nil
    }

    /// How the combination reads in a menu.
    static var describedDefault: String { "⌥Space" }
}
