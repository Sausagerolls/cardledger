import SwiftUI
import SwiftData
import AVFoundation

/// Find a card by scanning its QR (real device) or typing its short code (works anywhere,
/// including the Simulator which has no camera).
struct ScanView: View {
    @Environment(\.modelContext) private var context
    @State private var manualCode = ""
    @State private var foundCard: Card?
    @State private var notFound = false

    private var cameraAvailable: Bool {
        AVCaptureDevice.default(for: .video) != nil
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: Theme.spacing4) {
                if cameraAvailable {
                    QRScannerRepresentable { code in handleScanned(code) }
                        .frame(maxWidth: .infinity).frame(height: 320)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusLarge))
                        .overlay(RoundedRectangle(cornerRadius: Theme.radiusLarge).stroke(Theme.accent, lineWidth: 3))
                        .padding(.horizontal, Theme.spacing4)
                    Text("Point the camera at a card's QR code").font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                } else {
                    EmptyStateView(icon: "camera.metering.unknown", title: "No camera",
                                   message: "Camera isn't available here. Enter a short code below to find a card.")
                }

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

                Spacer()
            }
            .padding(.top, Theme.spacing4)
            .background(Theme.background)
            .navigationTitle("Scan")
            .navigationDestination(item: $foundCard) { card in CardDetailView(card: card) }
            .alert("No card found", isPresented: $notFound) {
                Button("OK", role: .cancel) {}
            } message: { Text("No card matches that code.") }
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
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else { return }
        session.addInput(input)

        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { return }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.qr]

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        view.layer.addSublayer(preview)
        self.preview = preview

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in self?.session.startRunning() }
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
