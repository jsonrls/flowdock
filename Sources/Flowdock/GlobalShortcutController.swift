import Carbon
import Foundation

extension Notification.Name {
    static let flowdockOpenRequested = Notification.Name("FlowdockOpenRequested")
}

@MainActor
final class GlobalShortcutController {
    private let hotKeyID = EventHotKeyID(signature: 0x4644_4F43, id: 1)  // FDOC
    private var hotKeyReference: EventHotKeyRef?
    private var eventHandlerReference: EventHandlerRef?

    func start() {
        registerGlobalHotKey()
    }

    func stop() {
        if let hotKeyReference {
            UnregisterEventHotKey(hotKeyReference)
            self.hotKeyReference = nil
        }

        if let eventHandlerReference {
            RemoveEventHandler(eventHandlerReference)
            self.eventHandlerReference = nil
        }
    }

    private func registerGlobalHotKey() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return noErr }

                var pressedHotKey = EventHotKeyID()
                let parameterStatus = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &pressedHotKey
                )

                guard parameterStatus == noErr, pressedHotKey.id == 1 else {
                    return parameterStatus
                }

                let controller = Unmanaged<GlobalShortcutController>
                    .fromOpaque(userData)
                    .takeUnretainedValue()

                DispatchQueue.main.async {
                    controller.requestOpen()
                }
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerReference
        )

        guard handlerStatus == noErr else { return }

        let hotKeyStatus = RegisterEventHotKey(
            UInt32(kVK_Space),
            UInt32(optionKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyReference
        )

        if hotKeyStatus != noErr, let eventHandlerReference {
            RemoveEventHandler(eventHandlerReference)
            self.eventHandlerReference = nil
        }
    }

    private func requestOpen() {
        NotificationCenter.default.post(name: .flowdockOpenRequested, object: nil)
    }
}
