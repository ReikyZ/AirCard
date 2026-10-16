import Foundation
import SQLite3

enum MiniMaxTokenError: Error {
    case notFound
    case unreadable
}

/// Open-platform token already stored by MiniMax Code. Nothing here is written into the repo.
enum MiniMaxTokenStore {
    static func tokens() throws -> [String] {
        var found: [String] = []
        var unreadable = false
        switch runtimeToken() {
        case .found(let token):
            found.append(token)
        case .missing:
            break
        case .unreadable:
            unreadable = true
        }
        switch cookieToken() {
        case .found(let token):
            if !found.contains(token) {
                found.append(token)
            }
        case .missing:
            break
        case .unreadable:
            unreadable = true
        }
        if found.isEmpty {
            throw unreadable ? MiniMaxTokenError.unreadable : MiniMaxTokenError.notFound
        }
        return found
    }

    private enum Read {
        case found(String)
        case missing
        case unreadable
    }

    /// `~/.minimax/local-runtime.auth.json`, `auth.accessToken`.
    private static func runtimeToken() -> Read {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".minimax/local-runtime.auth.json")
        guard FileManager.default.fileExists(atPath: url.path) else {
            return .missing
        }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            return .unreadable
        }
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let auth = json["auth"] as? [String: Any],
            let raw = auth["accessToken"] as? String
        else {
            return .unreadable
        }
        let token = TokenText.normalize(raw)
        return token.isEmpty ? .missing : .found(token)
    }

    /// Cookie `_token` on `www.minimaxi.com`, from MiniMax Code's cookie store.
    private static func cookieToken() -> Read {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/MiniMax/Cookies")
        guard FileManager.default.fileExists(atPath: url.path) else {
            return .missing
        }
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let opened = db else {
            sqlite3_close(db)
            return .unreadable
        }
        defer { sqlite3_close(opened) }
        sqlite3_busy_timeout(opened, 1500)

        var statement: OpaquePointer?
        let sql = "SELECT value FROM cookies WHERE name = ? AND host_key LIKE ? LIMIT 1;"
        guard sqlite3_prepare_v2(opened, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            return .unreadable
        }
        defer { sqlite3_finalize(statement) }

        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        let nameBound = "_token".withCString { sqlite3_bind_text(statement, 1, $0, -1, transient) }
        let hostBound = "%minimaxi.com".withCString { sqlite3_bind_text(statement, 2, $0, -1, transient) }
        guard nameBound == SQLITE_OK, hostBound == SQLITE_OK else {
            return .unreadable
        }
        let step = sqlite3_step(statement)
        if step == SQLITE_DONE {
            return .missing
        }
        guard step == SQLITE_ROW, let text = sqlite3_column_text(statement, 0) else {
            return .unreadable
        }
        let token = TokenText.normalize(String(cString: text))
        return token.isEmpty ? .missing : .found(token)
    }
}

enum MiniMaxRequest {
    static let remains = URL(string: "https://www.minimaxi.com/backend/account/token_plan/remains_percent")!

    static func fetch(token: String, session: URLSession) async throws -> Data {
        var request = URLRequest(url: remains)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(token, forHTTPHeaderField: "token")
        let (data, response) = try await session.data(for: request)
        guard response is HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        if data.isEmpty {
            throw URLError(.badServerResponse)
        }
        return data
    }
}

struct MiniMaxUsageProvider: UsageProvider {
    var window: MiniMaxWindow
    var tokenReader: @Sendable () throws -> [String]
    var session: URLSession

    var vendorName: String {
        switch window {
        case .fiveHour: return StickyRoster.minimax
        case .week: return StickyRoster.minimaxWeek
        }
    }

    init(
        window: MiniMaxWindow,
        tokenReader: @escaping @Sendable () throws -> [String] = { try MiniMaxTokenStore.tokens() },
        session: URLSession = .shared
    ) {
        self.window = window
        self.tokenReader = tokenReader
        self.session = session
    }

    func load(now: Date) async -> VendorSnapshot {
        let tokens: [String]
        do {
            tokens = try tokenReader()
        } catch MiniMaxTokenError.unreadable {
            return .unavailable(name: vendorName, reason: StickyCopy.unreadable)
        } catch {
            return .unavailable(name: vendorName, reason: StickyCopy.signedOut)
        }
        if tokens.isEmpty {
            return .unavailable(name: vendorName, reason: StickyCopy.signedOut)
        }

        var sawSignedOut = false
        for token in tokens {
            do {
                let data = try await MiniMaxRequest.fetch(token: token, session: session)
                let reading = try MiniMaxUsageDecoder.decode(data, window: window)
                return stickyUsageSnapshot(vendorName: vendorName, reading: reading, now: now)
            } catch MiniMaxUsageDecoder.Failure.signedOut {
                sawSignedOut = true
                continue
            } catch MiniMaxUsageDecoder.Failure.noAllowance {
                return .unavailable(name: vendorName, reason: StickyCopy.noAllowance)
            } catch is CancellationError {
                return VendorSnapshot(name: vendorName, kind: .loading)
            } catch let error as URLError where error.code == .cancelled {
                return VendorSnapshot(name: vendorName, kind: .loading)
            } catch {
                return .unavailable(name: vendorName, reason: StickyCopy.fetchFailed)
            }
        }
        return .unavailable(
            name: vendorName,
            reason: sawSignedOut ? StickyCopy.signedOut : StickyCopy.fetchFailed
        )
    }
}
