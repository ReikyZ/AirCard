import Darwin
import Foundation

extension Notification.Name {
    /// Posted after a Tampermonkey POST saves a cookie and optionally decodes usage.
    static let stickyMimoBridgeUpdate = Notification.Name("StickyMimoBridgeUpdate")
}

/// Payload from the localhost bridge. Cookie values are never logged.
struct MimoBridgeUpdate: @unchecked Sendable {
    var snapshot: VendorSnapshot?
    var shouldRefresh: Bool
}

/// Loopback-only HTTP receiver for the Mimo Tampermonkey userscript.
final class MimoBridgeServer: @unchecked Sendable {
    static let shared = MimoBridgeServer()
    static let port: UInt16 = 17_321
    static let path = "/mimo-usage"

    private let queue = DispatchQueue(label: "local.sticky.mimo-bridge")
    private var listenFD: Int32 = -1
    private var source: DispatchSourceRead?

    func start() {
        queue.async { [weak self] in
            self?.startLocked()
        }
    }

    func stop() {
        queue.async { [weak self] in
            self?.stopLocked()
        }
    }

    private func stopLocked() {
        source?.cancel()
        source = nil
        if listenFD >= 0 {
            Darwin.close(listenFD)
            listenFD = -1
        }
    }

    private func startLocked() {
        guard listenFD < 0 else { return }

        let fd = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return }

        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = Self.port.bigEndian
        addr.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.bind(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0, Darwin.listen(fd, 8) == 0 else {
            Darwin.close(fd)
            return
        }

        listenFD = fd
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in
            self?.acceptOne()
        }
        source.setCancelHandler {
            Darwin.close(fd)
        }
        source.resume()
        self.source = source
    }

    private func acceptOne() {
        var addr = sockaddr_storage()
        var len = socklen_t(MemoryLayout<sockaddr_storage>.size)
        let client = withUnsafeMutablePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.accept(listenFD, sockPtr, &len)
            }
        }
        guard client >= 0 else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.serve(client)
        }
    }

    private func serve(_ client: Int32) {
        defer { Darwin.close(client) }
        var buffer = Data()
        var chunk = [UInt8](repeating: 0, count: 16 * 1024)
        while buffer.count < 512 * 1024 {
            let n = chunk.withUnsafeMutableBytes { raw in
                Darwin.recv(client, raw.baseAddress, raw.count, 0)
            }
            if n <= 0 { break }
            buffer.append(contentsOf: chunk.prefix(n))
            if let response = tryHandle(buffer) {
                response.withUnsafeBytes { raw in
                    guard let base = raw.baseAddress else { return }
                    _ = Darwin.send(client, base, raw.count, 0)
                }
                return
            }
            if buffer.range(of: Data("\r\n\r\n".utf8)) != nil {
                // Headers complete but body incomplete; keep reading until content-length satisfied or fail.
                continue
            }
        }
        let fail = Self.httpResponse(status: 400, body: #"{"ok":false,"error":"bad_request"}"#)
        fail.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            _ = Darwin.send(client, base, raw.count, 0)
        }
    }

    private func tryHandle(_ raw: Data) -> Data? {
        guard let headerEnd = raw.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let headerData = raw.subdata(in: raw.startIndex..<headerEnd.lowerBound)
        guard let headerText = String(data: headerData, encoding: .utf8) else {
            return Self.httpResponse(status: 400, body: #"{"ok":false,"error":"bad_headers"}"#)
        }
        let lines = headerText.split(separator: "\r\n", omittingEmptySubsequences: false)
        guard let requestLine = lines.first else {
            return Self.httpResponse(status: 400, body: #"{"ok":false,"error":"bad_request"}"#)
        }
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else {
            return Self.httpResponse(status: 400, body: #"{"ok":false,"error":"bad_request"}"#)
        }
        let method = String(parts[0]).uppercased()
        let path = String(parts[1]).split(separator: "?").first.map(String.init) ?? String(parts[1])

        var headers: [String: String] = [:]
        for line in lines.dropFirst() where !line.isEmpty {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespacesAndNewlines)
            headers[name] = value
        }

        if method == "OPTIONS" {
            return Self.httpResponse(status: 204, body: "", extraHeaders: [
                "Access-Control-Allow-Origin: *",
                "Access-Control-Allow-Methods: POST, OPTIONS",
                "Access-Control-Allow-Headers: Content-Type, Cookie",
            ])
        }

        guard method == "POST", path == Self.path || path == "/" else {
            return Self.httpResponse(status: 404, body: #"{"ok":false,"error":"not_found"}"#)
        }

        let contentLength = Int(headers["content-length"] ?? "0") ?? 0
        let bodyStart = headerEnd.upperBound
        let have = raw.count - bodyStart
        guard have >= contentLength else { return nil }
        let body = raw.subdata(in: bodyStart..<(bodyStart + max(contentLength, 0)))

        do {
            try ingest(body: body, headerCookie: headers["cookie"])
            return Self.httpResponse(status: 200, body: #"{"ok":true}"#, extraHeaders: [
                "Access-Control-Allow-Origin: *",
            ])
        } catch {
            return Self.httpResponse(status: 400, body: #"{"ok":false,"error":"ingest_failed"}"#, extraHeaders: [
                "Access-Control-Allow-Origin: *",
            ])
        }
    }

    private func ingest(body: Data, headerCookie: String?) throws {
        var cookieFromBody: String?
        var usageObject: Any?
        var currentObject: Any?

        if !body.isEmpty {
            let object = try JSONSerialization.jsonObject(with: body)
            guard let json = object as? [String: Any] else {
                throw MimoSessionError.notFound
            }
            if let cookie = json["cookie"] as? String {
                cookieFromBody = cookie
            }
            usageObject = json["usage"]
            currentObject = json["current"] ?? json["currentPlan"]
        }

        let cookieRaw = cookieFromBody ?? headerCookie
        guard let cookieRaw, !cookieRaw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MimoSessionError.notFound
        }
        try MimoSessionFile.saveCookieLine(cookieRaw)

        var snapshot: VendorSnapshot?
        if let usageObject {
            let usageData = try JSONSerialization.data(withJSONObject: usageObject)
            let usedPercent = try MimoUsageDecoder.decodeUsage(usageData)
            let cycle: (start: Date, end: Date)
            if let currentObject {
                let currentData = try JSONSerialization.data(withJSONObject: currentObject)
                cycle = try MimoUsageDecoder.decodeCycle(currentData)
            } else {
                let cookieLine = try MimoSessionFile.cookieLine()
                let currentData = try awaitFetch(url: MimoRequest.currentPlan, cookieLine: cookieLine)
                cycle = try MimoUsageDecoder.decodeCycle(currentData)
            }
            let reading = DashboardUsageReading(
                usedPercent: usedPercent,
                cycleStart: cycle.start,
                cycleEnd: cycle.end
            )
            snapshot = stickyUsageSnapshot(vendorName: StickyRoster.mimo, reading: reading, now: Date())
        }

        let update = MimoBridgeUpdate(snapshot: snapshot, shouldRefresh: snapshot == nil)
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .stickyMimoBridgeUpdate, object: update)
            if update.shouldRefresh {
                NotificationCenter.default.post(name: .stickyRefreshRequested, object: nil)
            }
        }
    }

    private func awaitFetch(url: URL, cookieLine: String) throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue(cookieLine, forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(MimoRequest.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(MimoRequest.referer, forHTTPHeaderField: "Referer")

        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<Data, Error> = .failure(URLError(.badServerResponse))
        URLSession.shared.dataTask(with: request) { data, response, error in
            defer { semaphore.signal() }
            if let error {
                result = .failure(error)
                return
            }
            guard
                let data,
                let http = response as? HTTPURLResponse,
                (200..<300).contains(http.statusCode)
            else {
                result = .failure(URLError(.badServerResponse))
                return
            }
            result = .success(data)
        }.resume()
        _ = semaphore.wait(timeout: .now() + 25)
        return try result.get()
    }

    private static func httpResponse(status: Int, body: String, extraHeaders: [String] = []) -> Data {
        let reason: String
        switch status {
        case 200: reason = "OK"
        case 204: reason = "No Content"
        case 400: reason = "Bad Request"
        case 404: reason = "Not Found"
        default: reason = "Error"
        }
        var headers = [
            "HTTP/1.1 \(status) \(reason)",
            "Content-Type: application/json; charset=utf-8",
            "Content-Length: \(body.utf8.count)",
            "Connection: close",
        ]
        headers.append(contentsOf: extraHeaders)
        return Data((headers.joined(separator: "\r\n") + "\r\n\r\n" + body).utf8)
    }
}
