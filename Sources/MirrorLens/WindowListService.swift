import CoreGraphics
import AppKit

/// 系统窗口列表服务：查询屏幕上所有窗口、按坐标识别窗口
enum WindowListService {

    /// 单个窗口描述
    struct WindowInfo {
        let id: CGWindowID
        let pid: Int32
        let name: String
        let owner: String
        let frame: CGRect
    }

    private static var selfPID: Int32 {
        NSRunningApplication.current.processIdentifier
    }

    /// 列出屏幕上的普通应用窗口（用于菜单栏「添加窗口」）
    static func listAppWindows() -> [WindowInfo] {
        rawWindows().compactMap { info in
            let pid = info[kCGWindowOwnerPID as String] as? Int32 ?? 0
            let layer = info[kCGWindowLayer as String] as? Int ?? 0

            // 过滤：非本应用、非系统层窗口、非零层（桌面/菜单栏等）
            guard pid != 0, pid != selfPID, layer == 0 else { return nil }
            guard let name = info[kCGWindowName as String] as? String, !name.isEmpty else { return nil }
            guard let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict) else { return nil }
            // 过滤过小窗口（菜单面板、Tooltip 等）
            guard bounds.width >= 120, bounds.height >= 60 else { return nil }

            let owner = info[kCGWindowOwnerName as String] as? String ?? ""
            let windowID = CGWindowID(info[kCGWindowNumber as String] as? Int ?? 0)
            return WindowInfo(id: windowID, pid: pid, name: name, owner: owner, frame: bounds)
        }
    }

    /// 查询屏幕坐标处最顶层的可捕获窗口
    /// - Parameters:
    ///   - point: 屏幕坐标（CG 坐标系，左上原点）
    ///   - excludedIDs: 需要排除的窗口 ID（如镜内窗口自身）
    /// - Returns: 命中窗口（含其信息）
    static func window(at point: CGPoint, excludedIDs: Set<CGWindowID>) -> WindowInfo? {
        rawWindows().first { info in
            let pid = info[kCGWindowOwnerPID as String] as? Int32 ?? 0
            let layer = info[kCGWindowLayer as String] as? Int ?? 0
            let windowID = CGWindowID(info[kCGWindowNumber as String] as? Int ?? 0)

            guard pid != 0, pid != selfPID, layer == 0 else { return false }
            guard !excludedIDs.contains(windowID) else { return false }
            guard let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict) else { return false }
            guard bounds.width >= 40, bounds.height >= 30 else { return false }

            return bounds.contains(point)
        }
        .map { info in
            let windowID = CGWindowID(info[kCGWindowNumber as String] as? Int ?? 0)
            let bounds = CGRect(dictionaryRepresentation: info[kCGWindowBounds as String] as! NSDictionary)!
            let name = info[kCGWindowName as String] as? String ?? ""
            let owner = info[kCGWindowOwnerName as String] as? String ?? ""
            let pid = info[kCGWindowOwnerPID as String] as? Int32 ?? 0
            return WindowInfo(id: windowID, pid: pid, name: name, owner: owner, frame: bounds)
        }
    }

    /// 按窗口 ID 查询窗口最新 frame（目标窗口可能被移动/缩放）
    static func windowFrame(id: CGWindowID) -> CGRect? {
        let list = rawWindows()
        guard let info = list.first(where: {
            (CGWindowID($0[kCGWindowNumber as String] as? Int ?? 0)) == id
        }),
        let boundsDict = info[kCGWindowBounds as String] as? NSDictionary else { return nil }
        return CGRect(dictionaryRepresentation: boundsDict)
    }

    // MARK: - Private

    private static func rawWindows() -> [[String: Any]] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        // CGWindowListCopyWindowInfo 返回自底向上排列，反转后即为 z-order 顶层优先
        return list.reversed()
    }
}
