import CoreGraphics
import AppKit

/// 事件注入服务：把镜内操作转发到目标窗口（CGEvent 全局注入）
/// 依赖「辅助功能」权限；无权限时注入静默失败。
enum EventForwarder {

    /// 注入一次鼠标点击（按下 + 抬起）
    static func postClick(at point: CGPoint) {
        postMouse(.leftMouseDown, at: point)
        postMouse(.leftMouseUp, at: point)
    }

    /// 注入鼠标按下
    static func postMouseDown(at point: CGPoint) {
        postMouse(.leftMouseDown, at: point)
    }

    /// 注入鼠标抬起
    static func postMouseUp(at point: CGPoint) {
        postMouse(.leftMouseUp, at: point)
    }

    /// 注入鼠标拖动
    static func postMouseDragged(at point: CGPoint) {
        postMouse(.leftMouseDragged, at: point)
    }

    /// 注入鼠标移动（悬停）
    static func postMouseMoved(at point: CGPoint) {
        postMouse(.mouseMoved, at: point)
    }

    /// 注入滚轮滚动
    /// - Parameter event: 源滚动事件（取 scrollingDelta）
    static func postScroll(from event: NSEvent) {
        let factor: Int32 = event.hasPreciseScrollingDeltas ? 4 : 12
        let deltaY = Int32(-event.scrollingDeltaY * CGFloat(factor))
        let deltaX = Int32(event.scrollingDeltaX * CGFloat(factor))
        guard deltaY != 0 || deltaX != 0 else { return }
        let scrollEvent = CGEvent(
            scrollWheelEvent2Source: nil,
            units: event.hasPreciseScrollingDeltas ? .pixel : .line,
            wheelCount: 2,
            wheel1: deltaY,
            wheel2: deltaX,
            wheel3: 0
        )
        scrollEvent?.post(tap: .cghidEventTap)
    }

    // MARK: - Private

    private static func postMouse(_ type: CGEventType, at point: CGPoint) {
        guard let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left) else { return }
        event.post(tap: .cghidEventTap)
    }
}
