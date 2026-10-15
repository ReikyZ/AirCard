import Foundation

enum CursorSessionError: Error {
    case notFound
    case unreadable
}

/// Cookie line from `Sticky/.cursor-session`. These dashboard calls do not read `state.vscdb`.
enum CursorSessionFile {
    static func cookieLine(fileURL: URL? = nil) throws -> String {
        let url: URL
        if let fileURL {
            url = fileURL
        } else if let located = locate() {
            url = located
        } else {
            throw CursorSessionError.notFound
        }
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw CursorSessionError.notFound
        }
        let text: String
        do {
            text = try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw CursorSessionError.unreadable
        }
        let line = text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? ""
        guard line.hasPrefix("WorkosCursorSessionToken="), line.count > "WorkosCursorSessionToken=".count else {
            throw CursorSessionError.notFound
        }
        return line
    }

    static func locate() -> URL? {
        var candidates: [URL] = []
        if let root = Bundle.main.object(forInfoDictionaryKey: "StickySourceRoot") as? String {
            let trimmed = root.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, !trimmed.contains("$(") {
                candidates.append(URL(fileURLWithPath: trimmed, isDirectory: true).appendingPathComponent(".cursor-session"))
            }
        }
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        var dir = cwd
        for _ in 0..<8 {
            candidates.append(dir.appendingPathComponent(".cursor-session"))
            candidates.append(dir.appendingPathComponent("Sticky/.cursor-session"))
            let parent = dir.deletingLastPathComponent()
            if parent.path == dir.path { break }
            dir = parent
        }
        for url in candidates where FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        return nil
    }
}

enum DashboardRequest {
    static let cursorPeriodUsage = URL(string: "https://cursor.com/api/dashboard/get-current-period-usage")!
    static let grokSandUsage = URL(string: "https://cursor.com/api/dashboard/get-sand-usage-status")!

    static func fetch(url: URL, cookieLine: String, session: URLSession) async throws -> Data {
        do {
            return try await send(url: url, method: "POST", cookieLine: cookieLine, session: session)
        } catch {
            return try await send(url: url, method: "GET", cookieLine: cookieLine, session: session)
        }
    }

    private static func send(url: URL, method: String, cookieLine: String, session: URLSession) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = method
        if method == "POST" {
            request.httpBody = Data("{}".utf8)
        }
        request.timeoutInterval = 20
        request.setValue(cookieLine, forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        // cursor.com rejects a state-changing POST whose Origin is missing.
        request.setValue("https://cursor.com", forHTTPHeaderField: "Origin")
        request.setValue("https://cursor.com/dashboard", forHTTPHeaderField: "Referer")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return data
    }
}

struct CursorUsageProvider: UsageProvider {
    var vendorName: String { StickyRoster.cursor }
    var cookieReader: @Sendable () throws -> String
    var session: URLSession

    init(
        cookieReader: @escaping @Sendable () throws -> String = { try CursorSessionFile.cookieLine() },
        session: URLSession = .shared
    ) {
        self.cookieReader = cookieReader
        self.session = session
    }

    func load(now: Date) async -> VendorSnapshot {
        await loadDashboard(
            vendorName: vendorName,
            endpoint: DashboardRequest.cursorPeriodUsage,
            cookieReader: cookieReader,
            session: session,
            decode: CursorPeriodUsageDecoder.decode,
            now: now
        )
    }
}

struct GrokBotUsageProvider: UsageProvider {
    var vendorName: String { StickyRoster.grokBot }
    var cookieReader: @Sendable () throws -> String
    var session: URLSession

    init(
        cookieReader: @escaping @Sendable () throws -> String = { try CursorSessionFile.cookieLine() },
        session: URLSession = .shared
    ) {
        self.cookieReader = cookieReader
        self.session = session
    }

    func load(now: Date) async -> VendorSnapshot {
        await loadDashboard(
            vendorName: vendorName,
            endpoint: DashboardRequest.grokSandUsage,
            cookieReader: cookieReader,
            session: session,
            decode: GrokSandUsageDecoder.decode,
            now: now
        )
    }
}

private func loadDashboard(
    vendorName: String,
    endpoint: URL,
    cookieReader: @Sendable () throws -> String,
    session: URLSession,
    decode: (Data) throws -> DashboardUsageReading,
    now: Date
) async -> VendorSnapshot {
    let cookieLine: String
    do {
        cookieLine = try cookieReader()
    } catch CursorSessionError.unreadable {
        return .unavailable(name: vendorName, reason: StickyCopy.unreadable)
    } catch {
        return .unavailable(name: vendorName, reason: StickyCopy.signedOut)
    }

    do {
        let data = try await DashboardRequest.fetch(url: endpoint, cookieLine: cookieLine, session: session)
        let reading = try decode(data)
        return stickyUsageSnapshot(vendorName: vendorName, reading: reading, now: now)
    } catch is CancellationError {
        return VendorSnapshot(name: vendorName, kind: .loading)
    } catch let error as URLError where error.code == .cancelled {
        return VendorSnapshot(name: vendorName, kind: .loading)
    } catch {
        return .unavailable(name: vendorName, reason: StickyCopy.fetchFailed)
    }
}
