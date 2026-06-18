import SwiftUI
import SwiftData
import AVFoundation
import UIKit

/// Find a card by scanning its QR (real device) or typing its short code (works anywhere,
/// including the Simulator which has no camera).
struct ScanView: View {
    @Environment(\.modelContext) private var context
    @State private var manualCode = ""
    @State private var foundCard: Card?
    @State private var notFound = false
    @State private var camStatus = AVCaptureDevice.authorizationStatus(for: .video)

    private func requestCameraIfNeeded() {
        guard camStatus == .notDetermined else { return }
        AVCaptureDevice.requestAccess(for: .video) { granted in
            DispatchQueue.main.async {
                camStatus = granted ? .authorized : .denied
            }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: Theme.spacing4) {
                cameraSection

                SurfaceCard {
                    VStack(alignment: .leading, spacing: Theme.spacing2) {
                        Text("Find by short code").font(.headline)
                        HStack {
                            TextField("e.g. DBF-7K3Q", text: $manualCode)
                                .textInputAutocapitalization(.characters).autocorrectionDisabled()
                                .font(.mono)
                            Button("Find") { handleScanned(manualCode) }
                                .buttonStyle(.borderedProminent)
                                .disabled(manualCode.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                }
                .padding(.horizontal, Theme.spacing4)
            }
            .padding(.top, Theme.spacing4)
            .padding(.bottom, Theme.spacing4)
            .background(Theme.background)
            .navigationTitle("Scan")
            .onAppear(perform: requestCameraIfNeeded)
            .navigationDestination(item: $foundCard) { card in CardDetailView(card: card) }
            .alert("No card found", isPresented: $notFound) {
                Button("OK", role: .cancel) {}
            } message: { Text("No card matches that code.") }
        }
    }

    @ViewBuilder private var cameraSection: some View {
        switch camStatus {
        case .authorized:
            // Flexible height: the camera fills the space above the code box and shrinks
            // (rather than getting shoved off-screen) when the keyboard shows.
            QRScannerRepresentable { code in handleScanned(code) }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusLarge))
                .overlay(RoundedRectangle(cornerRadius: Theme.radiusLarge).stroke(Theme.accent, lineWidth: 3))
                .overlay(alignment: .bottom) {
                    Text("Point the camera at a card's QR code")
                        .font(.caption).foregroundStyle(.white)
                        .padding(8).background(.black.opacity(0.4), in: Capsule())
                        .padding(.bottom, 10)
                }
                .padding(.horizontal, Theme.spacing4)
        case .denied, .restricted:
            VStack(spacing: Theme.spacing3) {
                EmptyStateView(icon: "camera.fill", title: "Camera access off",
                               message: "Allow camera access to scan QR codes, or find a card by its short code below.")
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
                .buttonStyle(.bordered)
            }
            Spacer(minLength: 0)
        default:
            EmptyStateView(icon: "camera.metering.unknown", title: "Camera unavailable",
                           message: "Enter a short code below to find a card.")
            Spacer(minLength: 0)
        }
    }

    private func handleScanned(_ raw: String) {
        // Accept either a raw short code or a cardledger://card/<code> deep link.
        let code: String
        if let url = URL(string: raw), url.scheme == "cardledger" {
            code = url.lastPathComponent
        } else {
            code = raw.trimmingCharacters(in: .whitespaces)
        }
        if let card = CardLookup.find(code: code, in: context) {
            foundCard = card
        } else {
            notFound = true
        }
    }
}

/// Thin AVFoundation wrapper that reports decoded QR strings.
struct QRScannerRepresentable: UIViewControllerRepresentable {
    var onFound: (String) -> Void

    func makeUIViewController(context: Context) -> QRScannerController {
        let controller = QRScannerController()
        controller.onFound = onFound
        return controller
    }
    func updateUIViewController(_ controller: QRScannerController, context: Context) {}
}

final class QRScannerController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onFound: ((String) -> Void)?
    private let session = AVCaptureSession()
    private var preview: AVCaptureVideoPreviewLayer?
    private var didFind = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device) else { return }

        session.beginConfiguration()
        if session.canAddInput(input) { session.addInput(input) }
        let output = AVCaptureMetadataOutput()
        if session.canAddOutput(output) {
            session.addOutput(output)
            output.setMetadataObjectsDelegate(self, queue: .main)
            // Only request types the output actually supports (else this throws).
            if output.availableMetadataObjectTypes.contains(.qr) {
                output.metadataObjectTypes = [.qr]
            }
        }
        session.commitConfiguration()

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        view.layer.addSublayer(preview)
        self.preview = preview

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in self?.session.startRunning() }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if session.isRunning { DispatchQueue.global(qos: .userInitiated).async { [weak self] in self?.session.stopRunning() } }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        preview?.frame = view.bounds
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput,
                        didOutput objects: [AVMetadataObject],
                        from connection: AVCaptureConnection) {
        guard !didFind,
              let object = objects.first as? AVMetadataMachineReadableCodeObject,
              let value = object.stringValue else { return }
        didFind = true
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        onFound?(value)
    }
}
