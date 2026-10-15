import Foundation

@MainActor
final class NoteModel: ObservableObject {
    @Published private(set) var rows: [VendorSnapshot]
    private let providers: [any UsageProvider]
    private var generation = 0

    init(providers: [any UsageProvider]? = nil) {
        let resolved = providers ?? Self.liveProviders()
        self.providers = resolved
        self.rows = resolved.map(\.placeholder)
    }

    static func liveProviders() -> [any UsageProvider] {
        var providers: [any UsageProvider] = [CursorUsageProvider(), GrokUsageProvider()]
        for vendor in StickyRoster.pending {
            providers.append(UnavailableProvider(vendorName: vendor.name, reason: vendor.reason))
        }
        return providers
    }

    /// Refreshes when the note appears, then about every five minutes.
    func run() async {
        await refresh()
        while !Task.isCancelled {
            do {
                try await Task.sleep(nanoseconds: 5 * 60 * 1_000_000_000)
            } catch {
                break
            }
            if Task.isCancelled { break }
            await refresh()
        }
    }

    func refresh(now: Date = Date()) async {
        generation += 1
        let ticket = generation
        let providers = self.providers
        let results = await withTaskGroup(of: (Int, VendorSnapshot).self) { group -> [(Int, VendorSnapshot)] in
            for (index, provider) in providers.enumerated() {
                group.addTask {
                    let snapshot = await provider.load(now: now)
                    return (index, snapshot)
                }
            }
            var collected: [(Int, VendorSnapshot)] = []
            for await item in group {
                collected.append(item)
            }
            return collected
        }
        guard ticket == generation else { return }
        for (index, snapshot) in results {
            apply(snapshot, at: index)
        }
    }

    private func apply(_ snapshot: VendorSnapshot, at index: Int) {
        guard rows.indices.contains(index) else { return }
        // A cancelled load reports `.loading` so it does not wipe a real reading.
        if case .loading = snapshot.kind { return }
        rows[index] = snapshot
    }
}
