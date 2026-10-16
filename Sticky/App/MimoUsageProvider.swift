import Foundation

enum MimoSessionError: Error {
    case notFound
    case unreadable
}

/// Cookie line from `Sticky/.mimo-session`. A missing file is 未登录.
enum MimoSessionFile {
    static let planManageURL = URL(string: "https://platform.xiaomimimo.com/console/plan-manage")!

    static func cookieLine(fileURL: URL? = nil) throws -> String {
        let url: URL
        if let fileURL {
            url = fileURL
        } else if let located = locate() {
            url = located
        } else {
            throw MimoSessionError.notFound
        }
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw MimoSessionError.notFound
        }
        let text: String
        do {
            text = try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw MimoSessionError.unreadable
        }
        return try normalizeCookieLine(text)
    }

    /// Writes the Cookie header value into the gitignored session file. Never logs the value.
    static func saveCookieLine(_ raw: String) throws {
        let line = try normalizeCookieLine(raw)
        guard let url = writeURL() else {
            throw MimoSessionError.unreadable
        }
        do {
            try line.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            throw MimoSessionError.unreadable
        }
    }

    static func normalizeCookieLine(_ text: String) throws -> String {
        var line = text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? ""
        if line.lowercased().hasPrefix("cookie:") {
            line = String(line.dropFirst("cookie:".count)).trimmingCharacters(in: .whitespaces)
        }
        guard line.contains("="), line.count > "xiaomichatbot_serviceToken=".count else {
            throw MimoSessionError.notFound
        }
        return line
    }

    static func locate() -> URL? {
        for url in candidateURLs() where FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        return nil
    }

    /// Preferred path for a new session file (StickySourceRoot), else an existing locate hit.
    static func writeURL() -> URL? {
        if let preferred = preferredURL() {
            return preferred
        }
        return locate()
    }

    private static func preferredURL() -> URL? {
        if let root = Bundle.main.object(forInfoDictionaryKey: "StickySourceRoot") as? String {
            let trimmed = root.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, !trimmed.contains("$(") {
                return URL(fileURLWithPath: trimmed, isDirectory: true).appendingPathComponent(".mimo-session")
            }
        }
        return nil
    }

    private static func candidateURLs() -> [URL] {
        var candidates: [URL] = []
        if let preferred = preferredURL() {
            candidates.append(preferred)
        }
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        var dir = cwd
        for _ in 0..<8 {
            candidates.append(dir.appendingPathComponent(".mimo-session"))
            candidates.append(dir.appendingPathComponent("Sticky/.mimo-session"))
            let parent = dir.deletingLastPathComponent()
            if parent.path == dir.path { break }
            dir = parent
        }
        return candidates
    }
}

enum MimoRequest {
    static let usage = URL(string: "https://platform.xiaomimimo.com/api/v1/tokenPlan/usage")!
    static let currentPlan = URL(string: "https://platform.xiaomimimo.com/api/v1/tokenPlan/current")!
    static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/129.0.0.0 Safari/537.36"
    static let referer = "https://platform.xiaomimimo.com/"

    /// GET first. A rejection is retried with a browser User-Agent and Referer, then POST `{}`.
    static func fetch(url: URL, cookieLine: String, session: URLSession) async throws -> Data {
        if let data = try? await send(url: url, method: "GET", cookieLine: cookieLine, session: session, browser: false) {
            return data
        }
        if let data = try? await send(url: url, method: "GET", cookieLine: cookieLine, session: session, browser: true) {
            return data
        }
        return try await send(url: url, method: "POST", cookieLine: cookieLine, session: session, browser: true)
    }

    private static func send(
        url: URL,
        method: String,
        cookieLine: String,
        session: URLSession,
        browser: Bool
    ) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = method
        if method == "POST" {
            request.httpBody = Data("{}".utf8)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        request.timeoutInterval = 20
        request.setValue(cookieLine, forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if browser {
            request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
            request.setValue(referer, forHTTPHeaderField: "Referer")
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return data
    }
}

struct MimoUsageProvider: UsageProvider {
    var vendorName: String { StickyRoster.mimo }
    var cookieReader: @Sendable () throws -> String
    var session: URLSession

    init(
        cookieReader: @escaping @Sendable () throws -> String = { try MimoSessionFile.cookieLine() },
        session: URLSession = .shared
    ) {
        self.cookieReader = cookieReader
        self.session = session
    }

    func load(now: Date) async -> VendorSnapshot {
        let cookieLine: String
        do {
            cookieLine = try cookieReader()
        } catch MimoSessionError.unreadable {
            return .unavailable(name: vendorName, reason: StickyCopy.unreadable)
        } catch {
            return .unavailable(name: vendorName, reason: StickyCopy.signedOut)
        }

        do {
            async let usageData = MimoRequest.fetch(url: MimoRequest.usage, cookieLine: cookieLine, session: session)
            async let cycleData = MimoRequest.fetch(url: MimoRequest.currentPlan, cookieLine: cookieLine, session: session)
            let usedPercent = try MimoUsageDecoder.decodeUsage(try await usageData)
            let cycle = try MimoUsageDecoder.decodeCycle(try await cycleData)
            let reading = DashboardUsageReading(
                usedPercent: usedPercent,
                cycleStart: cycle.start,
                cycleEnd: cycle.end
            )
            return stickyUsageSnapshot(vendorName: vendorName, reading: reading, now: now)
        } catch is CancellationError {
            return VendorSnapshot(name: vendorName, kind: .loading)
        } catch let error as URLError where error.code == .cancelled {
            return VendorSnapshot(name: vendorName, kind: .loading)
        } catch {
            return .unavailable(name: vendorName, reason: StickyCopy.fetchFailed)
        }
    }
}

func stickyUsageSnapshot(vendorName: String, reading: DashboardUsageReading, now: Date) -> VendorSnapshot {
    let remaining = UsageMath.remainingPercent(usedPercent: reading.usedPercent)
    let fraction = remaining / 100
    let days = UsageMath.resetDays(cycleEnd: reading.cycleEnd, now: now)
    let cycleSeconds = max(0, reading.cycleEnd.timeIntervalSince(reading.cycleStart))
    let elapsed = UsageMath.cycleElapsedFraction(start: reading.cycleStart, end: reading.cycleEnd, now: now)
    let label = UsageMath.remainingLabel(cycleEnd: reading.cycleEnd, now: now)
    return VendorSnapshot(
        name: vendorName,
        kind: .usage(
            percent: UsageMath.percentPoints(fraction: fraction),
            fill: fraction,
            resetDays: days,
            cycleSeconds: cycleSeconds,
            elapsed: elapsed,
            label: label
        )
    )
}
