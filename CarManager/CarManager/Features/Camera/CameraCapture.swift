import SwiftUI
import AVFoundation
import PhotosUI

/// Owns the capture session. All session work runs on one serial queue, as AVFoundation
/// requires; the UI only sees `state` and the captured bytes.
final class CameraController: NSObject, @unchecked Sendable, AVCapturePhotoCaptureDelegate {
    enum State: Equatable { case idle, running, unavailable, denied }

    let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "camera.session")
    private var configured = false
    private var continuation: CheckedContinuation<Data, Error>?

    @MainActor private(set) var state: State = .idle
    @MainActor var onStateChange: ((State) -> Void)?

    @MainActor
    func start() async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .notDetermined:
            guard await AVCaptureDevice.requestAccess(for: .video) else { return set(.denied) }
        case .denied, .restricted:
            return set(.denied)
        default: break
        }
        let ok = await withCheckedContinuation { (done: CheckedContinuation<Bool, Never>) in
            queue.async { [self] in
                if !configured { configured = configure() }
                if configured && !session.isRunning { session.startRunning() }
                done.resume(returning: configured)
            }
        }
        set(ok ? .running : .unavailable)
    }

    func stop() {
        queue.async { [session] in if session.isRunning { session.stopRunning() } }
    }

    func capture() async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                self.continuation = continuation
                output.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
            }
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        queue.async { [self] in
            if let data = photo.fileDataRepresentation() { continuation?.resume(returning: data) }
            else { continuation?.resume(throwing: error ?? DomainError.ai(.noTextRecognized)) }
            continuation = nil
        }
    }

    private func configure() -> Bool {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input), session.canAddOutput(output) else { return false }
        session.beginConfiguration()
        session.sessionPreset = .photo
        session.addInput(input)
        session.addOutput(output)
        session.commitConfiguration()
        return true
    }

    @MainActor private func set(_ state: State) {
        self.state = state
        onStateChange?(state)
    }
}

private struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ view: PreviewView, context: Context) {}
}

/// The capture screen shared by receipt, dashboard and damage scans (Figma 17 / 32):
/// a framed viewfinder, one shutter button and a library fallback.
struct CaptureScreen: View {
    let title: String
    let symbol: String
    let hint: String
    var subhint: String?
    let onClose: () -> Void
    let onImage: (Data) -> Void

    @State private var camera = CameraController()
    @State private var cameraState: CameraController.State = .idle
    @State private var isCapturing = false
    @State private var photo: PhotosPickerItem?
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Button(action: onClose) {
                    Image(systemName: "xmark").font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                        .frame(width: 40, height: 40).background(Circle().fill(Color.white.opacity(0.051)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
                .accessibilityIdentifier("cameraClose")
                Text(title).font(.system(size: 20, weight: .bold)).tracking(-0.5).foregroundStyle(.white)
                Spacer()
            }
            .padding(.horizontal, DS.Layout.gutter)
            .padding(.top, 12)

            viewfinder
                .padding(.horizontal, DS.Layout.gutter)
                .padding(.top, 20)

            VStack(spacing: 4) {
                Text(hint).font(DS.Text.subheadline).foregroundStyle(.white)
                if let subhint { Text(subhint).font(DS.Text.caption).foregroundStyle(DS.Colors.textSecondary) }
            }
            .multilineTextAlignment(.center)
            .padding(.top, 16)

            Spacer(minLength: 16)

            Button(action: shoot) {
                ZStack {
                    Circle().fill(DS.Gradients.accentButton).frame(width: 68, height: 68)
                    if isCapturing { ProgressView().tint(.white) }
                    else { Image(systemName: "camera").font(.system(size: 22, weight: .semibold)).foregroundStyle(.white) }
                }
                .shadow(color: DS.Colors.accent.opacity(0.45), radius: 16, y: 6)
            }
            .buttonStyle(.plain)
            .disabled(cameraState != .running || isCapturing)
            .opacity(cameraState == .running ? 1 : 0.4)
            .accessibilityLabel("Capture")
            .accessibilityIdentifier("cameraCapture")

            PhotosPicker(selection: $photo, matching: .images) {
                Text("Choose from library").font(.system(size: 13, weight: .semibold)).foregroundStyle(DS.Colors.accent)
            }
            .padding(.top, 14)
            .padding(.bottom, 24)
            .accessibilityIdentifier("cameraLibrary")
        }
        .background(DS.Colors.background.ignoresSafeArea())
        .task {
            camera.onStateChange = { cameraState = $0 }
            await camera.start()
        }
        .onDisappear { camera.stop() }
        .onChange(of: photo) { _, item in
            guard let item else { return }
            Task { if let data = try? await item.loadTransferable(type: Data.self) { onImage(data) } }
        }
    }

    private var viewfinder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: DS.Layout.surfaceRadius).fill(Color.white.opacity(0.03))
            if cameraState == .running {
                CameraPreview(session: camera.session)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Layout.surfaceRadius))
            } else {
                VStack(spacing: 12) {
                    Image(systemName: symbol).font(.system(size: 34, weight: .light)).foregroundStyle(Color.white.opacity(0.35))
                    switch cameraState {
                    case .denied:
                        Text("Camera access is off").font(DS.Text.subheadline).foregroundStyle(.white)
                        Button("Open Settings") { if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) } }
                            .font(.system(size: 13, weight: .semibold)).foregroundStyle(DS.Colors.accent)
                    case .unavailable:
                        Text("No camera here — choose a photo instead").font(DS.Text.caption).foregroundStyle(DS.Colors.textSecondary)
                    default: EmptyView()
                    }
                }
            }
            ViewfinderBrackets().padding(14)
        }
        .overlay(RoundedRectangle(cornerRadius: DS.Layout.surfaceRadius).strokeBorder(DS.Colors.hairline))
        .frame(maxHeight: .infinity)
        .layoutPriority(1)
    }

    private func shoot() {
        isCapturing = true
        Task {
            defer { isCapturing = false }
            if let data = try? await camera.capture() { onImage(data) }
        }
    }
}

/// The four accent corners of the Figma viewfinder.
private struct ViewfinderBrackets: View {
    var body: some View {
        GeometryReader { proxy in
            let length: CGFloat = 26, w = proxy.size.width, h = proxy.size.height
            Path { p in
                p.move(to: CGPoint(x: 0, y: length)); p.addLine(to: .zero); p.addLine(to: CGPoint(x: length, y: 0))
                p.move(to: CGPoint(x: w - length, y: 0)); p.addLine(to: CGPoint(x: w, y: 0)); p.addLine(to: CGPoint(x: w, y: length))
                p.move(to: CGPoint(x: 0, y: h - length)); p.addLine(to: CGPoint(x: 0, y: h)); p.addLine(to: CGPoint(x: length, y: h))
                p.move(to: CGPoint(x: w - length, y: h)); p.addLine(to: CGPoint(x: w, y: h)); p.addLine(to: CGPoint(x: w, y: h - length))
            }
            .stroke(DS.Colors.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
        }
        .allowsHitTesting(false)
    }
}
