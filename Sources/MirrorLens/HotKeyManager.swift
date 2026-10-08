import Carbon.HIToolbox
import AppKit

/// 全局快捷键管理器（Carbon RegisterEventHotKey）
/// 热键在应用不处于前台时依然全局生效。
final class HotKeyManager {

    /// 快捷键的 Carbon 修饰键位常量
    struct Modifiers {
        static let option: UInt32 = UInt32(optionKey)
        static let command: UInt32 = UInt32(cmdKey)
        static let shift: UInt32 = UInt32(shiftKey)
        static let control: UInt32 = UInt32(controlKey)
    }

    /// 常用虚拟键码（与文档 3.2 键位方案对应）
    enum KeyCode: UInt32 {
        case upArrow = 126
        case downArrow = 125
        case leftArrow = 123
        case rightArrow = 124
    }

    private static let hotKeySignature: OSType = 0x4D524C53 // "MRLS"

    private var handlerRef: EventHandlerRef?
    private var hotKeyRefs: [UInt32: EventHotKeyRef] = [:]
    private var actions: [UInt32: () -> Void] = [:]
    private var nextID: UInt32 = 1

    init() {
        installEventHandler()
    }

    deinit {
        for ref in hotKeyRefs.values {
            UnregisterEventHotKey(ref)
        }
        if let handlerRef {
            RemoveEventHandler(handlerRef)
        }
    }

    /// 注册一个全局快捷键
    /// - Parameters:
    ///   - keyCode: 虚拟键码（如 kVK_ANSI_1、kVK_UpArrow）
    ///   - modifiers: Carbon 修饰键位组合（如 Modifiers.option）
    ///   - action: 触发回调（主线程）
    /// - Returns: 热键 ID（取消注册用）
    @discardableResult
    func register(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) -> UInt32 {
        let id = nextID
        nextID += 1

        var hotKeyRef: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: Self.hotKeySignature, id: id)
        let status = RegisterEventHotKey(
            keyCode, modifiers, hotKeyID,
            GetApplicationEventTarget(), 0, &hotKeyRef
        )
        guard status == noErr, let hotKeyRef else {
            NSLog("[MirrorLens] 热键注册失败 keyCode=\(keyCode) modifiers=\(modifiers)")
            return 0
        }

        hotKeyRefs[id] = hotKeyRef
        actions[id] = action
        return id
    }

    /// 注销热键
    func unregister(id: UInt32) {
        guard let ref = hotKeyRefs.removeValue(forKey: id) else { return }
        UnregisterEventHotKey(ref)
        actions.removeValue(forKey: id)
    }

    // MARK: - Carbon 事件处理

    private func installEventHandler() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let userData else { return noErr }
                let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()

                var hotKeyID = EventHotKeyID()
                let err = GetEventParameter(
                    event, EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID), nil,
                    MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID
                )
                guard err == noErr else { return noErr }

                if let action = manager.actions[hotKeyID.id] {
                    DispatchQueue.main.async(execute: action)
                }
                return noErr
            },
            1, &eventType, selfPtr, &handlerRef
        )
    }
}
