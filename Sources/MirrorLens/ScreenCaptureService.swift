import ScreenCaptureKit
import CoreMedia
import CoreImage
import CoreGraphics

/// 基于 ScreenCaptureKit 的窗口级实时捕获服务
final class ScreenCaptureService: NSObject, SCStreamOutput, SCStreamDelegate {

    enum CaptureError: Error, LocalizedError {
        case windowNotFound
        case permissionDenied
        case captureFailed(String)

        var errorDescription: String? {
            switch self {
            case .windowNotFound:
                return "未找到该窗口，它可能已被关闭"
            case .permissionDenied:
                return "缺少屏幕录制权限，请在系统设置中授权"
            case .captureFailed(let reason):
                return "捕获失败：\(reason)"
            }
        }
    }

    private var stream: SCStream?
    private var onFrame: ((CGImage?) -> Void)?
    private var currentConfig = SCStreamConfiguration()
    private let captureQueue = DispatchQueue(label: "com.mirrorlens.capture", qos: .userInitiated)
    private let ciContext = CIContext()

    var isCapturing: Bool { stream != nil }

    /// 开始捕获指定窗口的实时画面
    /// - Parameters:
    ///   - windowID: 目标窗口 ID
    ///   - frameHandler: 每帧回调（主线程；nil 表示捕获中断）
    func start(windowID: CGWindowID, frameHandler: @escaping (CGImage?) -> Void) async throws {
        await stop()

        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            throw CaptureError.permissionDenied
        }

        guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
            throw CaptureError.windowNotFound
        }

        let filter = SCContentFilter(desktopIndependentWindow: window)

        let config = SCStreamConfiguration()
        config.width = max(Int(window.frame.width), 64)
        config.height = max(Int(window.frame.height), 64)
        config.minimumFrameInterval = CMTime(value: 1, timescale: 15) // 15 FPS
        config.showsCursor = false
        config.queueDepth = 3
        currentConfig = config

        onFrame = frameHandler
        let newStream = SCStream(filter: filter, configuration: config, delegate: self)
        do {
            try newStream.addStreamOutput(self, type: .screen, sampleHandlerQueue: captureQueue)
            try await newStream.startCapture()
        } catch {
            NSLog("[MirrorLens] 启动捕获失败: \(error)")
            throw CaptureError.captureFailed(error.localizedDescription)
        }
        stream = newStream
    }

    /// 停止捕获
    func stop() async {
        if let stream {
            do { try await stream.stopCapture() } catch {}
        }
        stream = nil
        onFrame = nil
    }

    /// 切换画面中是否显示光标（操作模式显示，查看模式隐藏）
    func setShowCursor(_ show: Bool) async {
        guard currentConfig.showsCursor != show else { return }
        currentConfig.showsCursor = show
        guard let stream else { return }
        do {
            try await stream.updateConfiguration(currentConfig)
        } catch {
            NSLog("[MirrorLens] 更新光标显示配置失败: \(error)")
        }
    }

    // MARK: - SCStreamOutput

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let image = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = ciContext.createCGImage(image, from: image.extent) else { return }
        let handler = onFrame
        DispatchQueue.main.async {
            handler?(cgImage)
        }
    }

    // MARK: - SCStreamDelegate

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        NSLog("[MirrorLens] 捕获流停止: \(error.localizedDescription)")
        let handler = onFrame
        DispatchQueue.main.async {
            handler?(nil)
        }
        self.stream = nil
        onFrame = nil
    }
}
