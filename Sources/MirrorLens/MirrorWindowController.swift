import AppKit

/// 单个镜内窗口的控制器：
/// 管理悬浮面板、内容视图、窗口捕获生命周期与快捷键操作
final class MirrorWindowController {

    // MARK: - 属性

    let panel: MirrorPanel
    let mirrorView: MirrorView
    private let captureService = ScreenCaptureService()

    /// 当前捕获的窗口信息
    private(set) var capturedWindow: WindowListService.WindowInfo?

    /// 基础标题（操作模式时加前缀）
    private var baseTitle = "镜内"

    /// 当前是否处于操作模式（事件转发到目标窗口）
    private(set) var isInteractionMode = false

    var title: String {
        isInteractionMode ? "操作中 · \(baseTitle)" : baseTitle
    }

    var isCapturing: Bool { capturedWindow != nil }

    /// 被删除回调（AppDelegate 清理数组）
    var onDestroy: (() -> Void)?

    private var scale: CGFloat = 1.0
    private var opacity: CGFloat = 1.0

    /// 操作模式下是否已完成首次激活目标应用
    private var interactionActivated = false

    // MARK: - 初始化

    init(frame: NSRect = NSRect(x: 80, y: 80, width: 320, height: 240)) {
        panel = MirrorPanel.makeMirrorPanel(frame: frame)
        mirrorView = MirrorView(frame: NSRect(origin: .zero, size: frame.size))
        panel.contentView = mirrorView

        mirrorView.hasContent = false
        mirrorView.onClose = { [weak self] in
            self?.clearCapture()
        }
        mirrorView.onResize = { [weak self] _ in
            self?.updateScaleFromWindow()
        }
        setupInteraction()
        applyTitle()
        panel.orderFrontRegardless()
    }

    // MARK: - 捕获

    /// 开始捕获指定窗口
    func startCapture(window: WindowListService.WindowInfo) {
        capturedWindow = window
        baseTitle = "镜内 · \(window.name.isEmpty ? window.owner : window.name)"
        mirrorView.hasContent = true
        applyTitle()

        let windowID = window.id
        Task {
            do {
                try await captureService.start(windowID: windowID) { [weak self] image in
                    self?.mirrorView.setFrameImage(image)
                }
            } catch {
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.showCaptureError(error)
                }
            }
        }
    }

    /// 清除捕获（停止画面，恢复占位状态）
    func clearCapture() {
        exitInteraction()
        capturedWindow = nil
        baseTitle = "镜内"
        mirrorView.hasContent = false
        mirrorView.setFrameImage(nil)
        applyTitle()
        Task {
            await captureService.stop()
        }
    }

    private func showCaptureError(_ error: Error) {
        capturedWindow = nil
        baseTitle = "镜内 · 捕获失败"
        mirrorView.hasContent = false
        applyTitle()
        let alert = NSAlert()
        alert.messageText = "无法捕获窗口"
        alert.informativeText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        alert.alertStyle = .warning
        alert.addButton(withTitle: "好")
        alert.runModal()
    }

    /// 窗口捕获中断（流停止，如目标窗口关闭）
    func handleCaptureInterrupted() {
        guard capturedWindow != nil else { return }
        let name = baseTitle
        clearCapture()
        baseTitle = "\(name)（已断开）"
        applyTitle()
    }

    // MARK: - 快捷键操作

    /// 等比例放大 / 缩小（每次 ±10%）
    func zoom(by delta: CGFloat) {
        let target = min(max(scale * (1 + delta), 0.5), 4.0)
        let factor = target / scale
        scale = target
        mirrorView.scaleWindow(by: factor)
        updateScaleFromWindow()
    }

    /// 调节内容透明度（步进 0.1，范围 0.1~1.0）
    func adjustOpacity(by delta: CGFloat) {
        opacity = min(max(opacity + delta, 0.1), 1.0)
        mirrorView.contentOpacity = opacity
    }

    /// 移动窗口（步进 20pt）
    func moveBy(dx: CGFloat, dy: CGFloat) {
        var frame = panel.frame
        frame.origin.x += dx
        frame.origin.y += dy
        panel.setFrame(frame, display: true)
    }

    /// 删除窗口（停止捕获 + 关闭面板）
    func destroy() {
        clearCapture()
        panel.close()
        onDestroy?()
    }

    // MARK: - 操作模式（在镜内运行程序）

    private func setupInteraction() {
        mirrorView.onEnterInteraction = { [weak self] in
            self?.enterInteraction()
        }
        mirrorView.onExitInteraction = { [weak self] in
            self?.exitInteraction()
        }
        mirrorView.interactionHandler = { [weak self] action, point in
            self?.handleInteraction(action, at: point)
        }
        mirrorView.interactionScrollHandler = { [weak self] event in
            self?.handleInteractionScroll(event)
        }
    }

    /// 进入操作模式：镜内点击/滚动/键盘转发到目标窗口
    func enterInteraction() {
        guard isCapturing, !isInteractionMode else { return }
        isInteractionMode = true
        interactionActivated = false
        mirrorView.interactionMode = true
        applyTitle()
        Task {
            await captureService.setShowCursor(true)
        }
    }

    /// 退出操作模式，恢复纯查看
    func exitInteraction() {
        guard isInteractionMode else { return }
        isInteractionMode = false
        mirrorView.interactionMode = false
        interactionActivated = false
        applyTitle()
        Task {
            await captureService.setShowCursor(false)
        }
    }

    private func applyTitle() {
        mirrorView.title = title
    }

    private func handleInteraction(_ action: MirrorView.InteractionAction, at localPoint: NSPoint) {
        guard let target = targetScreenPoint(from: localPoint) else { return }
        if !interactionActivated {
            interactionActivated = true
            activateTargetApp()
        }
        switch action {
        case .move: EventForwarder.postMouseMoved(at: target)
        case .down: EventForwarder.postMouseDown(at: target)
        case .drag: EventForwarder.postMouseDragged(at: target)
        case .up: EventForwarder.postMouseUp(at: target)
        }
    }

    private func handleInteractionScroll(_ event: NSEvent) {
        guard isInteractionMode else { return }
        EventForwarder.postScroll(from: event)
    }

    /// 激活目标应用（让注入的键盘/鼠标事件被其接收）
    private func activateTargetApp() {
        guard let pid = capturedWindow?.pid else { return }
        NSRunningApplication(processIdentifier: pid)?.activate(options: [.activateAllWindows])
    }

    /// 把镜内视图坐标映射为目标窗口屏幕坐标（考虑 letterbox 等比显示）
    private func targetScreenPoint(from localPoint: NSPoint) -> CGPoint? {
        guard let window = capturedWindow,
              let frame = WindowListService.windowFrame(id: window.id) else { return nil }

        let contentRect = mirrorView.contentRectForInteraction
        let containerSize = contentRect.size
        let imageSize = mirrorView.lastFrameImageSize ?? containerSize
        guard containerSize.width > 0, containerSize.height > 0, imageSize.width > 0, imageSize.height > 0 else {
            return nil
        }

        // aspectFit：画面居中显示，计算实际显示区域
        let scale = min(containerSize.width / imageSize.width, containerSize.height / imageSize.height)
        let fitted = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let fittedRect = NSRect(
            x: contentRect.minX + (containerSize.width - fitted.width) / 2,
            y: contentRect.minY + (containerSize.height - fitted.height) / 2,
            width: fitted.width,
            height: fitted.height
        )
        guard fittedRect.contains(localPoint) else { return nil }

        let fx = (localPoint.x - fittedRect.minX) / fittedRect.width
        let fy = 1 - (localPoint.y - fittedRect.minY) / fittedRect.height // 视图坐标 → CG 左上原点
        return CGPoint(
            x: frame.minX + fx * frame.width,
            y: frame.minY + fy * frame.height
        )
    }

    /// 高亮拖入提示
    func setDropHighlight(_ highlighted: Bool) {
        mirrorView.isDropHighlighted = highlighted
    }

    /// 窗口 frame 是否包含某屏幕坐标
    func frameContains(screenPoint: CGPoint) -> Bool {
        panel.frame.contains(screenPoint)
    }

    // MARK: - Private

    private func updateScaleFromWindow() {
        let base: CGFloat = 320
        scale = panel.frame.width / base
        scale = min(max(scale, 0.5), 4.0)
    }
}
