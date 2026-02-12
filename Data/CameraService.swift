@preconcurrency import AVFoundation
import Observation

extension AVCaptureSession: @unchecked Sendable {}

@MainActor
@Observable
final class CameraService {
    let session: AVCaptureSession = AVCaptureSession()

    private(set) var isAuthorized: Bool = false
    private(set) var hasCheckedAccess: Bool = false
    private var isConfigured: Bool = false

    // Request camera permission. This must be async to show the system prompt.
    // 请求相机权限，必须异步执行以弹出系统权限提示。
    func requestAuthorization() async {
        let granted = await requestVideoAccess()
        isAuthorized = granted
        hasCheckedAccess = true
    }

    // Configure the capture session once after permission is granted.
    // 在获得权限后仅配置一次会话，避免重复添加输入。
    func configureIfNeeded() {
        guard isAuthorized, !isConfigured else { return }

        session.beginConfiguration()
        session.sessionPreset = .photo

        if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) {
            do {
                let input = try AVCaptureDeviceInput(device: device)
                if session.canAddInput(input) {
                    session.addInput(input)
                }
            } catch {
                session.commitConfiguration()
                return
            }
        }

        session.commitConfiguration()
        isConfigured = true
    }

    // Start the session on a background queue to avoid blocking UI.
    // 在后台线程启动会话，避免阻塞主线程。
    func startSession() {
        guard isConfigured, !session.isRunning else { return }
        DispatchQueue.global(qos: .userInitiated).async { [session] in
            session.startRunning()
        }
    }

    // Stop the session on a background queue to keep UI responsive.
    // 在后台线程停止会话，保证界面流畅。
    func stopSession() {
        guard session.isRunning else { return }
        DispatchQueue.global(qos: .userInitiated).async { [session] in
            session.stopRunning()
        }
    }

    // Normalize permission state for the async workflow.
    // 统一权限状态逻辑，便于异步流程处理。
    private func requestVideoAccess() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .video) { granted in
                    continuation.resume(returning: granted)
                }
            }
        default:
            return false
        }
    }
}
