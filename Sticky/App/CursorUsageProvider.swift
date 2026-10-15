import Foundation

struct CursorUsageProvider: UsageProvider {
    var vendorName: String { StickyRoster.cursor }

    var tokenReader: @Sendable () throws -> String
    var session: URLSession

    init(
        tokenReader: @escaping @Sendable () throws -> String = { try CursorStateDatabase.readAccessToken() },
        session: URLSession = .shared
    ) {
        self.tokenReader = tokenReader
        self.session = session
    }

    func load(now: Date) async -> VendorSnapshot {
        let token: String
        do {
            token = try tokenReader()
        } catch CursorTokenError.notFound {
            return .unavailable(name: vendorName, reason: StickyCopy.signedOut)
        } catch {
            return .unavailable(name: vendorName, reason: StickyCopy.unreadable)
        }

        do {
            let data = try await CursorDashboardAPI.fetchPeriodUsage(token: token, session: session)
            let reading = try PeriodUsageDecoder.decode(data)
            guard let fraction = UsageMath.remainingFraction(remaining: reading.remaining, limit: reading.limit) else {
                return .unavailable(name: vendorName, reason: StickyCopy.noAllowance)
            }
            // Current X Subscription pools refresh weekly, and `billingCycleEnd` can be
            // the billing date rather than the weekly usage reset. Use `billingCycleEnd` for now.
            let days = UsageMath.resetDays(cycleEnd: reading.cycleEnd, now: now)
            return VendorSnapshot(
                name: vendorName,
                kind: .usage(
                    percent: UsageMath.percentPoints(fraction: fraction),
                    fill: fraction,
                    resetDays: days
                )
            )
        } catch is CancellationError {
            return VendorSnapshot(name: vendorName, kind: .loading)
        } catch let error as URLError where error.code == .cancelled {
            return VendorSnapshot(name: vendorName, kind: .loading)
        } catch {
            return .unavailable(name: vendorName, reason: StickyCopy.fetchFailed)
        }
    }
}

enum CursorDashboardAPI {
    static let endpoint = URL(string: "https://api2.cursor.sh/aiserver.v1.DashboardService/GetCurrentPeriodUsage")!

    static func fetchPeriodUsage(token: String, session: URLSession) async throws -> Data {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.httpBody = Data("{}".utf8)
        request.timeoutInterval = 20
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Connect-RPC answers with binary protobuf unless JSON is accepted explicitly.
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return data
    }
}
