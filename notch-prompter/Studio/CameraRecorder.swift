// Caméra du mode studio : caméra du Mac, iPhone en Continuity Camera ou caméra USB, micro au choix, un .mov par passage.
import AVFoundation
import AppKit
import Combine
import SwiftUI

final class CameraRecorder: NSObject, ObservableObject, StudioRecorder, AVCaptureFileOutputRecordingDelegate {
    struct Device: Identifiable, Hashable { let id: String; let name: String }

    @Published private(set) var cameras: [Device] = []
    @Published private(set) var microphones: [Device] = []
    @Published var cameraID: String? { didSet { defaults.set(cameraID, forKey: "StudioCamera"); reconfigureIfRunning() } }
    @Published var microphoneID: String? { didSet { defaults.set(microphoneID, forKey: "StudioMicrophone"); reconfigureIfRunning() } }

    let session = AVCaptureSession()
    private let output = AVCaptureMovieFileOutput()
    private let queue = DispatchQueue(label: "notchprompter.camera")
    private let defaults = UserDefaults.standard
    private var configured = false
    private var stopContinuation: CheckedContinuation<URL, Error>?
    private var observers: [NSObjectProtocol] = []

    override init() {
        super.init()
        cameraID = defaults.string(forKey: "StudioCamera")
        microphoneID = defaults.string(forKey: "StudioMicrophone")
        refreshDevices()
        let nc = NotificationCenter.default
        for name in [AVCaptureDevice.wasConnectedNotification, AVCaptureDevice.wasDisconnectedNotification] {
            observers.append(nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.refreshDevices() })
        }
    }

    deinit { observers.forEach(NotificationCenter.default.removeObserver) }

    var elapsed: TimeInterval {
        let t = output.recordedDuration
        return t.isValid ? t.seconds : 0
    }

    func refreshDevices() {
        let video = AVCaptureDevice.DiscoverySession(deviceTypes: [.continuityCamera, .builtInWideAngleCamera, .external], mediaType: .video, position: .unspecified).devices
        let audio = AVCaptureDevice.DiscoverySession(deviceTypes: [.microphone, .external], mediaType: .audio, position: .unspecified).devices
        cameras = video.map { Device(id: $0.uniqueID, name: $0.localizedName) }
        microphones = audio.map { Device(id: $0.uniqueID, name: $0.localizedName) }
    }

    /// Caméra choisie, sinon l'iPhone en Continuity Camera s'il est là, sinon la caméra du Mac.
    private func videoDevice() -> AVCaptureDevice? {
        if let id = cameraID, let d = AVCaptureDevice(uniqueID: id) { return d }
        let all = AVCaptureDevice.DiscoverySession(deviceTypes: [.continuityCamera, .builtInWideAngleCamera, .external], mediaType: .video, position: .unspecified).devices
        return all.first { $0.deviceType == .continuityCamera } ?? all.first { $0.deviceType == .builtInWideAngleCamera } ?? all.first
    }

    private func audioDevice() -> AVCaptureDevice? {
        if let id = microphoneID, let d = AVCaptureDevice(uniqueID: id) { return d }
        return AVCaptureDevice.default(for: .audio)
    }

    // MARK: StudioRecorder

    /// Demande l'accès caméra et micro, configure la séance et allume la caméra pour l'aperçu.
    func prepare() async throws {
        guard await AVCaptureDevice.requestAccess(for: .video) else { throw StudioError("Accès à la caméra refusé : Réglages Système → Confidentialité → Caméra → NotchPrompter.") }
        guard await AVCaptureDevice.requestAccess(for: .audio) else { throw StudioError("Accès au micro refusé : Réglages Système → Confidentialité → Micro → NotchPrompter.") }
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            queue.async {
                do {
                    try self.configure()
                    if !self.session.isRunning { self.session.startRunning() }
                    c.resume()
                } catch { c.resume(throwing: error) }
            }
        }
    }

    func start(to url: URL) throws {
        if !configured || !session.isRunning {
            // Premier passage sans aperçu préparé : on configure de façon synchrone.
            try queue.sync {
                try configure()
                if !session.isRunning { session.startRunning() }
            }
        }
        guard !output.isRecording else { throw StudioError("Un enregistrement est déjà en cours") }
        output.startRecording(to: url, recordingDelegate: self)
    }

    func stop() async throws -> URL {
        guard output.isRecording else { throw StudioError("Aucun enregistrement en cours") }
        return try await withCheckedThrowingContinuation { c in
            stopContinuation = c
            output.stopRecording()
        }
    }

    func shutdown() {
        queue.async { if self.session.isRunning { self.session.stopRunning() } }
    }

    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo url: URL, from connections: [AVCaptureConnection], error: Error?) {
        // Une « erreur » peut accompagner un fichier valide (disque presque plein, durée max) : on garde le fichier s'il est fini.
        let finished = (error as NSError?)?.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool ?? (error == nil)
        let c = stopContinuation
        stopContinuation = nil
        if finished { c?.resume(returning: url) } else { c?.resume(throwing: error ?? StudioError("Enregistrement interrompu")) }
    }

    // MARK: Configuration

    private func configure() throws {
        guard let camera = videoDevice() else { throw StudioError("Aucune caméra trouvée. Branche l'iPhone ou ouvre le Mac.") }
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.inputs.forEach(session.removeInput)
        let videoInput = try AVCaptureDeviceInput(device: camera)
        guard session.canAddInput(videoInput) else { throw StudioError("La caméra « \(camera.localizedName) » est déjà utilisée") }
        session.addInput(videoInput)
        if let mic = audioDevice(), let audioInput = try? AVCaptureDeviceInput(device: mic), session.canAddInput(audioInput) {
            session.addInput(audioInput)
        }
        if !session.outputs.contains(output), session.canAddOutput(output) { session.addOutput(output) }
        // 4K quand la caméra le permet : un short 9:16 recadré dans du 16:9 garde alors 2160 px de haut.
        for preset in [AVCaptureSession.Preset.hd4K3840x2160, .hd1920x1080, .high] where session.canSetSessionPreset(preset) {
            session.sessionPreset = preset
            break
        }
        configured = true
    }

    private func reconfigureIfRunning() {
        guard configured, !output.isRecording else { return }
        queue.async { try? self.configure() }
    }
}

/// Aperçu de la caméra, en miroir comme un miroir de salle de bain.
struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.backgroundColor = NSColor.black.cgColor
        view.layer = layer
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let connection = (nsView.layer as? AVCaptureVideoPreviewLayer)?.connection, connection.isVideoMirroringSupported else { return }
        connection.automaticallyAdjustsVideoMirroring = false
        connection.isVideoMirrored = true
    }
}
