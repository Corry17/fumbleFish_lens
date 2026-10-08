import AppKit

/// 镜内悬浮面板：无边框、置顶、非激活（不抢占焦点）
final class MirrorPanel: NSPanel {

    /// 永远不成为 Key/Main 窗口 —— 摸鱼时不打断当前应用
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override var acceptsFirstResponder: Bool { false }

    static func makeMirrorPanel(frame: NSRect) -> MirrorPanel {
        let panel = MirrorPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.hasShadow = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isReleasedWhenClosed = false
        return panel
    }
}
