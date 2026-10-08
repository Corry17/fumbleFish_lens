import AppKit

/// 镜内窗口的内容视图：
/// - 顶部标题栏（显示捕获窗口名、关闭按钮）
/// - 中间内容层（显示捕获画面，等比缩放、可调透明度）
/// - 边缘缩放把手（直接拖动窗口缩放）
final class MirrorView: NSView {

    // MARK: - 常量

    static let minWindowWidth: CGFloat = 140
    static let minWindowHeight: CGFloat = 100

    private enum ResizeRegion {
        case none
        case topLeft, topRight, bottomLeft, bottomRight
        case left, right, top, bottom
    }

    // MARK: - 视图元素

    private let backgroundLayer = CALayer()
    private let titleBar = NSVisualEffectView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let closeButton = NSButton()
    private let contentContainer = NSView()
    private let placeholderLabel = NSTextField(labelWithString: "拖入任意窗口")
    private let highlightBorder = CALayer()

    /// 内容画面层（透明度、等比缩放作用于该层）
    private let contentLayer = CALayer()

    private var titleBarVisible = true

    // MARK: - 状态

    /// 交互动作（转发到目标窗口）
    enum InteractionAction {
        case move, down, drag, up
    }

    private var resizeRegion: ResizeRegion = .none
    private var isResizing = false
    private var resizeStartFrame: NSRect = .zero
    private var resizeStartPoint: NSPoint = .zero

    /// 操作模式：把点击/滚动转发到目标窗口（“在镜内运行程序”）
    var interactionMode = false

    /// 交互回调（由控制器实现坐标映射与事件注入）
    var interactionHandler: ((InteractionAction, NSPoint) -> Void)?
    var interactionScrollHandler: ((NSEvent) -> Void)?
    var onEnterInteraction: (() -> Void)?
    var onExitInteraction: (() -> Void)?

    var onClose: (() -> Void)?
    var onResize: ((NSRect) -> Void)?

    /// 内容区在视图坐标系中的位置（坐标映射用）
    var contentRectForInteraction: NSRect {
        contentContainer.frame
    }

    /// 最近一帧画面的原始尺寸（等比映射用）
    private(set) var lastFrameImageSize: CGSize?

    private var titleBarHeight: CGFloat { titleBarVisible ? 22 : 0 }

    // MARK: - 初始化

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) 未实现")
    }

    private func setup() {
        wantsLayer = true
        layer = backgroundLayer
        backgroundLayer.cornerRadius = 8
        backgroundLayer.masksToBounds = true
        backgroundLayer.backgroundColor = NSColor(calibratedWhite: 0.12, alpha: 0.92).cgColor

        // 内容容器（画面 + 占位）
        contentContainer.wantsLayer = true
        contentContainer.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.35).cgColor
        contentContainer.layer?.addSublayer(contentLayer)
        contentLayer.contentsGravity = .resizeAspect
        contentLayer.backgroundColor = NSColor.black.cgColor
        contentLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2

        // 占位提示
        placeholderLabel.font = .systemFont(ofSize: 12, weight: .medium)
        placeholderLabel.textColor = NSColor(white: 0.75, alpha: 0.8)
        placeholderLabel.alignment = .center
        placeholderLabel.isHidden = true
        placeholderLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        placeholderLabel.setContentHuggingPriority(.defaultHigh, for: .vertical)

        // 标题栏
        titleBar.material = .hudWindow
        titleBar.state = .active
        titleBar.blendingMode = .withinWindow

        titleLabel.font = .systemFont(ofSize: 10.5, weight: .medium)
        titleLabel.textColor = NSColor(white: 0.85, alpha: 0.9)
        titleLabel.lineBreakMode = .byTruncatingMiddle

        closeButton.isBordered = false
        closeButton.bezelStyle = .inline
        closeButton.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "关闭")
        closeButton.contentTintColor = NSColor(white: 0.85, alpha: 0.8)
        closeButton.target = self
        closeButton.action = #selector(closeClicked)
        closeButton.isHidden = true // 未捕获内容时不显示关闭按钮

        addSubview(contentContainer)
        addSubview(titleBar)
        titleBar.addSubview(titleLabel)
        titleBar.addSubview(closeButton)
        addSubview(placeholderLabel)

        // 高亮边框（拖入提示）
        highlightBorder.frame = bounds.insetBy(dx: -1, dy: -1)
        highlightBorder.borderWidth = 3
        highlightBorder.cornerRadius = 10
        highlightBorder.borderColor = NSColor.systemGreen.withAlphaComponent(0).cgColor
        highlightBorder.isHidden = true
        layer?.addSublayer(highlightBorder)

        startTracking()
        updateContentLayout()
    }

    // MARK: - 布局

    override func layout() {
        super.layout()
        updateContentLayout()
    }

    private func updateContentLayout() {
        let boundsSize = bounds.size
        backgroundLayer.frame = bounds
        highlightBorder.frame = bounds.insetBy(dx: -1, dy: -1)

        let titleHeight: CGFloat = titleBarVisible ? 22 : 0
        titleBar.frame = NSRect(x: 0, y: boundsSize.height - titleHeight,
                                width: boundsSize.width, height: titleHeight)
        titleLabel.frame = NSRect(x: 8, y: (titleHeight - 14) / 2,
                                  width: max(boundsSize.width - 52, 0), height: 14)
        closeButton.frame = NSRect(x: boundsSize.width - 24, y: (titleHeight - 16) / 2,
                                   width: 16, height: 16)
        closeButton.isHidden = !titleBarVisible || contentLayer.isHidden

        let contentFrame = NSRect(x: 0, y: 0, width: boundsSize.width, height: boundsSize.height - titleHeight)
        contentContainer.frame = contentFrame
        contentLayer.frame = contentContainer.bounds
        placeholderLabel.frame = contentFrame
        placeholderLabel.alignment = .center
    }

    // MARK: - 状态设置

    /// 设置捕获画面帧
    func setFrameImage(_ image: CGImage?) {
        if let image {
            contentLayer.contents = image
            contentLayer.isHidden = false
            placeholderLabel.isHidden = true
            lastFrameImageSize = CGSize(width: image.width, height: image.height)
        } else {
            contentLayer.contents = nil
            contentLayer.isHidden = true
            placeholderLabel.isHidden = hasContent ? true : false
        }
        closeButton.isHidden = !titleBarVisible || !hasContent
    }

    /// 设置内容是否就绪（用于占位提示）
    var hasContent: Bool = false {
        didSet {
            placeholderLabel.isHidden = hasContent
            if !hasContent {
                contentLayer.contents = nil
                contentLayer.isHidden = true
            }
            closeButton.isHidden = !titleBarVisible || !hasContent
        }
    }

    /// 标题文字
    var title: String = "" {
        didSet { titleLabel.stringValue = title }
    }

    /// 内容透明度（0.1 ~ 1.0）
    var contentOpacity: CGFloat = 1.0 {
        didSet {
            contentLayer.opacity = Float(contentOpacity)
        }
    }

    /// 拖入高亮
    var isDropHighlighted: Bool = false {
        didSet {
            highlightBorder.isHidden = false
            highlightBorder.borderColor = NSColor.systemGreen
                .withAlphaComponent(isDropHighlighted ? 1.0 : 0.0).cgColor
            if !isDropHighlighted {
                highlightBorder.isHidden = true
            }
        }
    }

    // MARK: - 鼠标事件（拖动窗口 / 边缘缩放）

    private func startTracking() {
        // .activeAlways：非激活悬浮窗也能收到 mouseMoved（操作模式依赖）
        let options: NSTrackingArea.Options = [.activeAlways,
                                               .mouseMoved, .mouseEnteredAndExited, .inVisibleRect]
        addTrackingArea(NSTrackingArea(rect: .zero, options: options, owner: self, userInfo: nil))
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if interactionMode {
            NSCursor.crosshair.set()
            if isInContentArea(point) {
                interactionHandler?(.move, point)
            }
            return
        }
        updateCursor(for: point)
    }

    override func mouseExited(with event: NSEvent) {
        if !isResizing && !interactionMode {
            resizeRegion = .none
            NSCursor.arrow.set()
        }
    }

    private func updateCursor(for point: NSPoint) {
        guard !isResizing else { return }
        resizeRegion = region(at: point)
        let cursor: NSCursor
        switch resizeRegion {
        case .topLeft, .bottomRight: cursor = .resizeUpDown
        case .topRight, .bottomLeft: cursor = .resizeLeftRight
        case .left, .right: cursor = .resizeLeftRight
        case .top, .bottom: cursor = .resizeUpDown
        case .none: cursor = .arrow
        }
        cursor.set()
    }

    private func region(at point: NSPoint) -> ResizeRegion {
        let edge: CGFloat = 7
        let w = bounds.width, h = bounds.height
        guard point.x >= 0, point.y >= 0, point.x <= w, point.y <= h else { return .none }
        let left = point.x <= edge, right = point.x >= w - edge
        let top = point.y >= h - edge, bottom = point.y <= edge
        if left && top { return .topLeft }
        if right && top { return .topRight }
        if left && bottom { return .bottomLeft }
        if right && bottom { return .bottomRight }
        if left { return .left }
        if right { return .right }
        if top { return .top }
        if bottom { return .bottom }
        return .none
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)

        if interactionMode {
            if isInContentArea(point) {
                // 内容区点击 → 转发到目标窗口
                interactionHandler?(.down, point)
            } else {
                // 标题栏点击 → 退出操作模式
                onExitInteraction?()
            }
            return
        }

        resizeRegion = region(at: point)
        isResizing = resizeRegion != .none
        if isResizing {
            resizeStartFrame = window?.frame ?? .zero
            resizeStartPoint = event.locationInWindow
            NSCursor.arrow.set()
        } else if isInContentArea(point) {
            // 内容区单击 → 进入操作模式（“在镜内运行程序”）
            onEnterInteraction?()
        } else {
            // 标题栏：交给窗口背景拖动逻辑（isMovableByWindowBackground）
            super.mouseDown(with: event)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        if interactionMode {
            let point = convert(event.locationInWindow, from: nil)
            if isInContentArea(point) {
                interactionHandler?(.drag, point)
            }
            return
        }
        guard isResizing, let window else { return }
        let dx = event.locationInWindow.x - resizeStartPoint.x
        let dy = event.locationInWindow.y - resizeStartPoint.y

        var newFrame = resizeStartFrame
        switch resizeRegion {
        case .left:
            newFrame.origin.x += dx
            newFrame.size.width -= dx
        case .right:
            newFrame.size.width += dx
        case .bottom:
            newFrame.origin.y += dy
            newFrame.size.height -= dy
        case .top:
            newFrame.size.height += dy
        case .topLeft:
            newFrame.origin.x += dx
            newFrame.size.width -= dx
            newFrame.size.height += dy
        case .topRight:
            newFrame.size.width += dx
            newFrame.size.height += dy
        case .bottomLeft:
            newFrame.origin.x += dx
            newFrame.size.width -= dx
            newFrame.origin.y += dy
            newFrame.size.height -= dy
        case .bottomRight:
            newFrame.size.width += dx
            newFrame.size.height -= dy
        case .none:
            return
        }

        // 最小尺寸约束
        if newFrame.width < Self.minWindowWidth {
            newFrame.origin.x = resizeStartFrame.origin.x + resizeStartFrame.width - Self.minWindowWidth
            newFrame.size.width = Self.minWindowWidth
        }
        if newFrame.height < Self.minWindowHeight {
            newFrame.origin.y = resizeStartFrame.origin.y + resizeStartFrame.height - Self.minWindowHeight
            newFrame.size.height = Self.minWindowHeight
        }

        window.setFrame(newFrame, display: true)
        onResize?(newFrame)
    }

    override func mouseUp(with event: NSEvent) {
        if interactionMode {
            let point = convert(event.locationInWindow, from: nil)
            if isInContentArea(point) {
                interactionHandler?(.up, point)
            }
            return
        }
        isResizing = false
        updateCursor(for: convert(event.locationInWindow, from: nil))
    }

    override func scrollWheel(with event: NSEvent) {
        if interactionMode {
            interactionScrollHandler?(event)
        }
    }

    /// 是否在内容区（标题栏之下）
    private func isInContentArea(_ point: NSPoint) -> Bool {
        point.y <= bounds.height - titleBarHeight
    }

    // MARK: - 快捷键缩放（等比）

    /// 按比例缩放窗口（0.5 ~ 4.0），保持内容宽高比
    func scaleWindow(by factor: CGFloat) {
        guard let window else { return }
        let newWidth = min(max(window.frame.width * factor, Self.minWindowWidth), 2400)
        let newHeight = min(max(window.frame.height * factor, Self.minWindowHeight), 1800)
        let oldFrame = window.frame
        var newFrame = NSRect(
            x: oldFrame.midX - newWidth / 2,
            y: oldFrame.midY - newHeight / 2,
            width: newWidth,
            height: newHeight
        )
        // 保持屏幕内
        if let screen = window.screen ?? NSScreen.main {
            let visible = screen.visibleFrame
            if newFrame.minX < visible.minX { newFrame.origin.x = visible.minX }
            if newFrame.minY < visible.minY { newFrame.origin.y = visible.minY }
            if newFrame.maxX > visible.maxX { newFrame.origin.x = visible.maxX - newFrame.width }
            if newFrame.maxY > visible.maxY { newFrame.origin.y = visible.maxY - newFrame.height }
        }
        window.setFrame(newFrame, display: true)
        onResize?(newFrame)
    }

    // MARK: - 动作

    @objc private func closeClicked() {
        onClose?()
    }
}
