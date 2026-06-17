import Foundation
import Network

/// An edit posted from the browser. Only the non-nil fields are applied, so the same
/// shape serves create (with `gameCode`) and partial updates.
struct EditRequest: Decodable {
    var shortCode: String?
    var gameCode: String?
    var name: String?
    var setName: String?
    var number: String?
    var rarity: String?
    var condition: String?      // raw CardCondition value, e.g. "NM"
    var quantity: Int?
    var purchasePrice: Double?
    var purchaseDate: String?   // "yyyy-MM-dd"
    var notes: String?
    var tags: [String]?
    var isSold: Bool?
    var salePrice: Double?
}

struct EditResult: Encodable {
    let ok: Bool
    let message: String
    let shortCode: String?
}

/// A tiny read-only HTTP server that serves the inventory to any browser on the same
/// network, and advertises itself over Bonjour (`_http._tcp`) so it appears as
/// `cardledger.local`. Runs only while the app is foreground (iOS suspends background
/// apps), which is fine for "phone on the desk, view on the PC".
@Observable
final class LANServer {
    static let shared = LANServer()

    private(set) var isRunning = false
    private(set) var activePort: UInt16 = 0
    var lastError: String?

    /// Applies an edit coming from the browser. Set by the UI; invoked on the main thread.
    /// Returns a result that's serialised back to the browser.
    var editHandler: ((_ action: String, _ request: EditRequest) -> EditResult)?

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.cardledger.lanserver")
    private let preferredPort: UInt16 = 8080

    // Thread-safe data snapshot, pushed from the UI whenever the inventory changes.
    private let lock = NSLock()
    private var payload = Data("{}".utf8)
    private var csv = ""
    private var pdf = Data()                      // QR sheet for printing
    private var photos: [String: [Data]] = [:]   // shortCode -> [jpeg]

    func updateData(payload: Data, csv: String, pdf: Data, photos: [String: [Data]]) {
        lock.lock(); defer { lock.unlock() }
        self.payload = payload; self.csv = csv; self.pdf = pdf; self.photos = photos
    }

    // MARK: Authorisation
    // Browsers get a session cookie and must be approved in the app before they see
    // anything. Until then they're served a "waiting for approval" page.

    struct PendingDevice: Identifiable, Equatable { let id: String; let ip: String }
    /// Devices waiting for the user to approve (observed by the UI, mutated on main).
    private(set) var pendingDevices: [PendingDevice] = []

    private var approvedSessions = Set<String>()   // lock-guarded
    private var deniedSessions = Set<String>()     // lock-guarded
    private var seenSessions = Set<String>()       // lock-guarded (dedupe prompts)

    private enum AuthState: String { case approved, denied, pending }

    private func authState(for sid: String, ip: String) -> AuthState {
        lock.lock()
        if approvedSessions.contains(sid) { lock.unlock(); return .approved }
        if deniedSessions.contains(sid) { lock.unlock(); return .denied }
        let isNew = seenSessions.insert(sid).inserted
        lock.unlock()
        if isNew {
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.pendingDevices.contains(where: { $0.id == sid }) else { return }
                self.pendingDevices.append(PendingDevice(id: sid, ip: ip))
            }
        }
        return .pending
    }

    func approve(_ id: String) {
        lock.lock(); approvedSessions.insert(id); lock.unlock()
        pendingDevices.removeAll { $0.id == id }
    }
    func deny(_ id: String) {
        lock.lock(); deniedSessions.insert(id); lock.unlock()
        pendingDevices.removeAll { $0.id == id }
    }

    // MARK: Lifecycle

    func start() {
        guard listener == nil else { return }
        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            let listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: preferredPort) ?? .any)
            listener.service = NWListener.Service(name: "CardLedger", type: "_http._tcp")
            listener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    DispatchQueue.main.async {
                        self.activePort = listener.port?.rawValue ?? self.preferredPort
                        self.isRunning = true
                        self.lastError = nil
                    }
                case .failed:
                    // Most failures here are the network being torn down when the app is
                    // sent to the background, or a Wi-Fi change — not something the user
                    // did wrong. Show a plain-English message rather than a raw error.
                    DispatchQueue.main.async {
                        self.lastError = "The desktop server stopped because the connection changed — usually the app going to the background or switching Wi-Fi. Switch it back on to keep sharing."
                        self.isRunning = false
                    }
                    self.stop()
                default:
                    break
                }
            }
            listener.newConnectionHandler = { [weak self] conn in self?.accept(conn) }
            listener.start(queue: queue)
            self.listener = listener
        } catch {
            lastError = error.localizedDescription
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        lock.lock()
        approvedSessions.removeAll(); deniedSessions.removeAll(); seenSessions.removeAll()
        lock.unlock()
        DispatchQueue.main.async {
            self.isRunning = false
            self.activePort = 0
            self.pendingDevices.removeAll()   // re-authorise after a restart
        }
    }

    // MARK: Connections

    private func accept(_ conn: NWConnection) {
        conn.start(queue: queue)
        receive(conn, Data(), ip: Self.remoteIP(of: conn))
    }

    /// Accumulate bytes until a full HTTP request (headers + any body) has arrived.
    private func receive(_ conn: NWConnection, _ buffer: Data, ip: String) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 256 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { conn.cancel(); return }
            var buf = buffer
            if let data { buf.append(data) }
            if let parsed = self.parse(buf) {
                let response = self.route(method: parsed.method, path: parsed.path, sid: parsed.sid, body: parsed.body, ip: ip)
                conn.send(content: response, completion: .contentProcessed { _ in conn.cancel() })
            } else if isComplete || error != nil {
                conn.cancel()
            } else {
                self.receive(conn, buf, ip: ip)   // wait for the rest
            }
        }
    }

    static func remoteIP(of conn: NWConnection) -> String {
        if case let .hostPort(host, _) = conn.endpoint {
            switch host {
            case .ipv4(let a): return "\(a)".components(separatedBy: "%").first ?? "\(a)"
            case .ipv6(let a): return "\(a)".components(separatedBy: "%").first ?? "\(a)"
            case .name(let n, _): return n
            @unknown default: return "a device"
            }
        }
        return "a device"
    }

    /// Parse a request once headers + full body are present, else return nil to wait.
    private func parse(_ buffer: Data) -> (method: String, path: String, sid: String?, body: String)? {
        guard let text = String(data: buffer, encoding: .utf8),
              let headerEnd = text.range(of: "\r\n\r\n") else { return nil }
        let header = text[text.startIndex..<headerEnd.lowerBound]
        let lines = header.split(separator: "\r\n")
        guard let first = lines.first else { return nil }
        let parts = first.split(separator: " ")
        guard parts.count >= 2 else { return nil }
        let method = String(parts[0])
        let path = String(parts[1]).removingPercentEncoding ?? String(parts[1])

        var contentLength = 0
        var sid: String?
        for line in lines {
            let lower = line.lowercased()
            if lower.hasPrefix("content-length:") {
                contentLength = Int(line.split(separator: ":")[1].trimmingCharacters(in: .whitespaces)) ?? 0
            } else if lower.hasPrefix("cookie:") {
                let cookies = line.drop(while: { $0 != ":" }).dropFirst()
                for pair in cookies.split(separator: ";") {
                    let kv = pair.split(separator: "=", maxSplits: 1)
                    if kv.count == 2, kv[0].trimmingCharacters(in: .whitespaces) == "cl_sid" {
                        sid = kv[1].trimmingCharacters(in: .whitespaces)
                    }
                }
            }
        }
        let body = String(text[headerEnd.upperBound...])
        if body.utf8.count < contentLength { return nil }   // body still arriving
        return (method, path, sid, body)
    }

    private func route(method: String, path: String, sid: String?, body: String, ip: String) -> Data {
        // Resolve the browser's session; mint one (with a cookie) on first contact.
        var setCookie: [String: String] = [:]
        var session = sid ?? ""
        if session.isEmpty {
            session = UUID().uuidString
            setCookie["Set-Cookie"] = "cl_sid=\(session); Path=/; Max-Age=86400; SameSite=Lax"
        }
        let state = authState(for: session, ip: ip)

        // The waiting page polls this regardless of approval.
        if path == "/api/auth-status" {
            return response(contentType: "application/json; charset=utf-8",
                            body: Data("{\"status\":\"\(state.rawValue)\"}".utf8), extra: setCookie)
        }
        // Gate everything else until approved.
        guard state == .approved else {
            if path == "/" || path == "/index.html" {
                return response(contentType: "text/html; charset=utf-8",
                                body: Data(WebUI.gatePage(denied: state == .denied).utf8), extra: setCookie)
            }
            return response(status: "403 Forbidden", contentType: "text/plain",
                            body: Data("Awaiting approval in the CardLedger app.".utf8), extra: setCookie)
        }

        if method == "POST", path.hasPrefix("/api/card/") {
            return handleEdit(action: String(path.dropFirst("/api/card/".count)), body: body)
        }

        lock.lock(); defer { lock.unlock() }
        switch true {
        case path == "/" || path == "/index.html":
            return response(contentType: "text/html; charset=utf-8", body: Data(WebUI.page.utf8))
        case path == "/api/cards":
            return response(contentType: "application/json; charset=utf-8", body: payload)
        case path == "/export.csv":
            return response(contentType: "text/csv; charset=utf-8", body: Data(csv.utf8),
                            extra: ["Content-Disposition": "attachment; filename=\"CardLedger-Inventory.csv\""])
        case path == "/qr-sheet.pdf":
            return response(contentType: "application/pdf", body: pdf,
                            extra: ["Content-Disposition": "attachment; filename=\"CardLedger-QR-Sheet.pdf\""])
        case path.hasPrefix("/photo/"):
            return photoResponse(path)
        default:
            return notFound()
        }
    }

    private func handleEdit(action: String, body: String) -> Data {
        guard let handler = editHandler else {
            return json(EditResult(ok: false, message: "Editing unavailable", shortCode: nil))
        }
        guard let request = try? JSONDecoder().decode(EditRequest.self, from: Data(body.utf8)) else {
            return json(EditResult(ok: false, message: "Bad request", shortCode: nil))
        }
        var result = EditResult(ok: false, message: "No response", shortCode: nil)
        DispatchQueue.main.sync { result = handler(action, request) }   // SwiftData mutations on main
        return json(result)
    }

    private func json(_ result: EditResult) -> Data {
        let body = (try? JSONEncoder().encode(result)) ?? Data("{}".utf8)
        return response(contentType: "application/json; charset=utf-8", body: body)
    }

    private func photoResponse(_ path: String) -> Data {
        // /photo/<shortCode>/<index>
        let comps = path.split(separator: "/")
        guard comps.count == 3, let index = Int(comps[2]) else { return notFound() }
        let code = String(comps[1])
        guard let images = photos[code], index >= 0, index < images.count else { return notFound() }
        return response(contentType: "image/jpeg", body: images[index],
                        extra: ["Cache-Control": "max-age=300"])
    }

    // MARK: HTTP helpers

    private func response(status: String = "200 OK", contentType: String, body: Data, extra: [String: String] = [:]) -> Data {
        var head = "HTTP/1.1 \(status)\r\n"
        head += "Content-Type: \(contentType)\r\n"
        head += "Content-Length: \(body.count)\r\n"
        head += "Access-Control-Allow-Origin: *\r\n"
        head += "Connection: close\r\n"
        for (k, v) in extra { head += "\(k): \(v)\r\n" }
        head += "\r\n"
        return Data(head.utf8) + body
    }

    private func notFound() -> Data {
        response(status: "404 Not Found", contentType: "text/plain", body: Data("Not found".utf8))
    }

    // MARK: Addresses

    /// Wi-Fi IPv4 address of this device, for "http://<ip>:<port>".
    static func wifiIPAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let interface = ptr.pointee
            let family = interface.ifa_addr.pointee.sa_family
            guard family == UInt8(AF_INET) else { continue }
            let name = String(cString: interface.ifa_name)
            guard name == "en0" else { continue }   // Wi-Fi
            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                        &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST)
            address = String(cString: hostname)
        }
        return address
    }
}
