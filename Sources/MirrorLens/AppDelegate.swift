import AppKit
import CoreGraphics
import ApplicationServices

/// 应用主代理：菜单栏、拖入识别、权限引导、全局快捷键分发、镜子窗口管理
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    // MARK: - 属性

    private var statusItem: NSStatusItem!
    private let hotKeyManager = HotKeyManager()

    /// 所有镜内窗口
    private var mirrors: [MirrorWindowController] = []

    /// 快捷键作用目标：最近操作的镜子，无则第一个
    private weak var lastTouchedMirror: MirrorWindowController?
    private var activeMirror: MirrorWindowController? {
        lastTouchedMirror ?? mirrors.first
    }

    // 拖入识别状态
    private var dragSourceWindow: WindowListService.WindowInfo?
    private weak var dropHighlightMirror: MirrorWindowController?

    // 动态子菜单（保持对象引用以便 menuNeedsUpdate 刷新）
    private let addWindowsSubmenu = NSMenu()
    private let manageSubmenu = NSMenu()

    // MARK: - 生命周期

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        setupHotKeys()
        setupGlobalMouseMonitor()
        createMirrorWindow()
        checkScreenRecordingPermissionAtLaunch()
    }

    func applicationWillTerminate(_ notification: Notification) {
        for mirror in mirrors {
            mirror.clearCapture()
        }
    }

    // MARK: - 菜单栏

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "镜内")
        }
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        rebuildMenu()
        rebuildAddWindowsMenu()
        rebuildManageMenu()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        if menu === statusItem.menu {
            rebuildMenu()
        } else if menu === addWindowsSubmenu {
            rebuildAddWindowsMenu()
        } else if menu === manageSubmenu {
            rebuildManageMenu()
        }
    }

    private func rebuildMenu() {
        guard let statusItem else { return }
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        // 添加窗口
        let addItem = NSMenuItem(title: "添加窗口", action: nil, keyEquivalent: "")
        addWindowsSubmenu.delegate = self
        addItem.submenu = addWindowsSubmenu
        menu.addItem(addItem)

        // 窗口管理
        let manageItem = NSMenuItem(title: "窗口管理", action: nil, keyEquivalent: "")
        manageSubmenu.delegate = self
        manageItem.submenu = manageSubmenu
        menu.addItem(manageItem)

        menu.addItem(.separator())

        // 权限状态
        let screenOK = CGPreflightScreenCaptureAccess()
        let screenItem = NSMenuItem(
            title: "屏幕录制权限：\(screenOK ? "已授权" : "未授权")",
            action: screenOK ? nil : #selector(openScreenRecordingSettings),
            keyEquivalent: ""
        )
        screenItem.target = screenOK ? nil : self
        menu.addItem(screenItem)

        let axOK = AXIsProcessTrusted()
        let axItem = NSMenuItem(
            title: "辅助功能权限：\(axOK ? "已授权" : "未授权（拖入需要）")",
            action: axOK ? nil : #selector(openAccessibilitySettings),
            keyEquivalent: ""
        )
        axItem.target = axOK ? nil : self
        menu.addItem(axItem)

        menu.addItem(.separator())

        let newItem = NSMenuItem(title: "新建镜子窗口", action: #selector(newMirrorWindow), keyEquivalent: "")
        newItem.target = self
        menu.addItem(newItem)

        let quitItem = NSMenuItem(title: "退出镜内", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.target = NSApplication.shared
        menu.addItem(quitItem)
    }

    /// 「添加窗口」子菜单：列出所有可捕获的屏幕窗口
    private func rebuildAddWindowsMenu() {
        addWindowsSubmenu.removeAllItems()
        let windows = WindowListService.listAppWindows()
        guard !windows.isEmpty else {
            let empty = NSMenuItem(title: "没有可捕获的窗口", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            addWindowsSubmenu.addItem(empty)
            return
        }
        for window in windows {
            let item = NSMenuItem(
                title: "\(window.owner) — \(window.name)",
                action: #selector(captureWindow(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = window
            addWindowsSubmenu.addItem(item)
        }
    }

    /// 「窗口管理」子菜单：列出所有镜子（点击删除）＋ 新建
    private func rebuildManageMenu() {
        manageSubmenu.removeAllItems()
        if mirrors.isEmpty {
            let empty = NSMenuItem(title: "（没有镜子窗口）", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            manageSubmenu.addItem(empty)
        }
        for (index, mirror) in mirrors.enumerated() {
            let label = mirror.isCapturing ? "删除：\(mirror.title)" : "删除：空镜子 \(index + 1)"
            let item = NSMenuItem(title: label, action: #selector(destroyMirror(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = mirror
            manageSubmenu.addItem(item)
        }
        manageSubmenu.addItem(.separator())
        let newItem = NSMenuItem(title: "新建镜子窗口", action: #selector(newMirrorWindow), keyEquivalent: "")
        newItem.target = self
        manageSubmenu.addItem(newItem)
    }

    // MARK: - 窗口管理

    private func createMirrorWindow() {
        let mirror = MirrorWindowController()
        mirrors.append(mirror)
        lastTouchedMirror = mirror
    }

    private func removeMirror(_ mirror: MirrorWindowController) {
        mirrors.removeAll { $0 === mirror }
        mirror.destroy()
        if lastTouchedMirror === mirror {
            lastTouchedMirror = nil
        }
        if mirrors.isEmpty {
            createMirrorWindow()
        }
    }

    @objc private func newMirrorWindow() {
        createMirrorWindow()
    }

    @objc private func destroyMirror(_ sender: NSMenuItem) {
        guard let mirror = sender.representedObject as? MirrorWindowController else { return }
        removeMirror(mirror)
    }

    @objc private func captureWindow(_ sender: NSMenuItem) {
        guard let info = sender.representedObject as? WindowListService.WindowInfo else { return }
        let target = activeMirror ?? mirrors.first
        lastTouchedMirror = target
        target?.startCapture(window: info)
    }

    // MARK: - 全局快捷键（文档 3.2 键位方案）

    private func setupHotKeys() {
        let option = HotKeyManager.Modifiers.option
        let command = HotKeyManager.Modifiers.command
        let up = HotKeyManager.KeyCode.upArrow.rawValue
        let down = HotKeyManager.KeyCode.downArrow.rawValue
        let left = HotKeyManager.KeyCode.leftArrow.rawValue
        let right = HotKeyManager.KeyCode.rightArrow.rawValue

        // Option+↑/↓：内容等比例放大 / 缩小 10%
        hotKeyManager.register(keyCode: up, modifiers: option) { [weak self] in
            self?.activeMirror?.zoom(by: 0.1)
        }
        hotKeyManager.register(keyCode: down, modifiers: option) { [weak self] in
            self?.activeMirror?.zoom(by: -0.1)
        }
        // Option+←/→：内容透明度降低 / 提高 0.1
        hotKeyManager.register(keyCode: left, modifiers: option) { [weak self] in
            self?.activeMirror?.adjustOpacity(by: -0.1)
        }
        hotKeyManager.register(keyCode: right, modifiers: option) { [weak self] in
            self?.activeMirror?.adjustOpacity(by: 0.1)
        }
        // Cmd+方向键：移动窗口 20pt
        // （注：文档 3.2 移动原方案与缩放/透明度冲突，MVP 以 Cmd 修饰）
        hotKeyManager.register(keyCode: up, modifiers: command) { [weak self] in
            self?.activeMirror?.moveBy(dx: 0, dy: 20)
        }
        hotKeyManager.register(keyCode: down, modifiers: command) { [weak self] in
            self?.activeMirror?.moveBy(dx: 0, dy: -20)
        }
        hotKeyManager.register(keyCode: left, modifiers: command) { [weak self] in
            self?.activeMirror?.moveBy(dx: -20, dy: 0)
        }
        hotKeyManager.register(keyCode: right, modifiers: command) { [weak self] in
            self?.activeMirror?.moveBy(dx: 20, dy: 0)
        }
        // Option+Esc：退出操作模式（kVK_Escape = 53）
        hotKeyManager.register(keyCode: 53, modifiers: option) { [weak self] in
            self?.activeMirror?.exitInteraction()
        }
    }

    // MARK: - 拖入识别（全局鼠标事件）

    /// 拖入需要「辅助功能」权限；未授权时静默失败，菜单中提示
    private func setupGlobalMouseMonitor() {
        NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
        ) { [weak self] event in
            self?.handleGlobalMouse(event)
        }
    }

    private func handleGlobalMouse(_ event: NSEvent) {
        let point = event.locationInWindow // 全局事件坐标为屏幕坐标
        switch event.type {
        case .leftMouseDown:
            if let mirror = mirror(containing: point) {
                // 在镜子内按下：视为拖动镜子本身，不记录捕获源
                lastTouchedMirror = mirror
                dragSourceWindow = nil
            } else {
                // 在其他窗口按下：记录为潜在捕获源
                dragSourceWindow = WindowListService.window(
                    at: point,
                    excludedIDs: Set(mirrors.map { CGWindowID($0.panel.windowNumber) })
                )
            }
        case .leftMouseDragged:
            let target = mirror(containing: point)
            if target !== dropHighlightMirror {
                dropHighlightMirror?.setDropHighlight(false)
                dropHighlightMirror = target
                target?.setDropHighlight(true)
            }
        case .leftMouseUp:
            dropHighlightMirror?.setDropHighlight(false)
            if let mirror = dropHighlightMirror, let source = dragSourceWindow {
                lastTouchedMirror = mirror
                mirror.startCapture(window: source)
                NSLog("[MirrorLens] 拖入捕获 → \(source.owner) · \(source.name)")
            }
            dropHighlightMirror = nil
            dragSourceWindow = nil
        default:
            break
        }
    }

    private func mirror(containing point: CGPoint) -> MirrorWindowController? {
        mirrors.first { $0.frameContains(screenPoint: point) }
    }

    // MARK: - 权限

    private func checkScreenRecordingPermissionAtLaunch() {
        guard !CGPreflightScreenCaptureAccess() else { return }
        let alert = NSAlert()
        alert.messageText = "需要屏幕录制权限"
        alert.informativeText = "「镜内」需要屏幕录制权限，才能把窗口内容实时装进镜内。\n\n点击「打开设置」前往系统设置授权；授权后请重启「镜内」生效。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "打开设置")
        alert.addButton(withTitle: "稍后")
        if alert.runModal() == .alertFirstButtonReturn {
            openSystemSettings(section: "Privacy_ScreenCapture")
        }
    }

    @objc private func openScreenRecordingSettings() {
        openSystemSettings(section: "Privacy_ScreenCapture")
    }

    @objc private func openAccessibilitySettings() {
        openSystemSettings(section: "Privacy_Accessibility")
    }

    private func openSystemSettings(section: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(section)") else { return }
        NSWorkspace.shared.open(url)
    }
}
