import Foundation
#if canImport(AppKit)
import AppKit
#endif

public enum UsageState: Equatable {
    case loading
    case missingToken
    case ok(UsageSnapshot)
    /// API failed but we synthesized a snapshot from local JSONL.
    case estimated(UsageSnapshot, underlyingMessage: String)
    case error(String)

    public var snapshot: UsageSnapshot? {
        switch self {
        case .ok(let s): return s
        case .estimated(let s, _): return s
        default: return nil
        }
    }
}

@MainActor
public final class UsageRefresher: ObservableObject {
    @Published public private(set) var state: UsageState = .loading

    private let keychain: KeychainReading
    private let api: AnthropicUsageFetching
    private let aggregator: JSONLAggregating
    private let projectsDirectory: URL
    private let clock: @Sendable () -> Date

    /// Polling interval used when the popover is closed.
    public var backgroundInterval: TimeInterval = 300

    /// Polling interval used when the popover is visible.
    public var foregroundInterval: TimeInterval = 60

    private var refreshTask: Task<Void, Never>?
    private var loopTask: Task<Void, Never>?
    private var isPopoverOpen = false
    private var isPaused = false
    private var observersInstalled = false

    public init(
        keychain: KeychainReading = KeychainService(),
        api: AnthropicUsageFetching = AnthropicAPIClient(),
        aggregator: JSONLAggregating = JSONLParser(),
        projectsDirectory: URL = JSONLParser.defaultProjectsDirectory(),
        clock: @escaping @Sendable () -> Date = { Date() },
        autoStart: Bool = true
    ) {
        self.keychain = keychain
        self.api = api
        self.aggregator = aggregator
        self.projectsDirectory = projectsDirectory
        self.clock = clock
        if autoStart { start() }
    }

    deinit {
        refreshTask?.cancel()
        loopTask?.cancel()
    }

    // MARK: - Lifecycle

    public func start() {
        installSleepObservers()
        scheduleLoop()
        Task { await self.refresh() }
    }

    public func popoverDidOpen() {
        isPopoverOpen = true
        scheduleLoop()
        Task { await self.refresh() }
    }

    public func popoverDidClose() {
        isPopoverOpen = false
        scheduleLoop()
    }

    public func refreshNow() {
        Task { await self.refresh() }
    }

    // MARK: - Refresh

    /// Runs one refresh cycle. Public for testability — UI never calls directly.
    public func refresh() async {
        let token: String
        do {
            token = try keychain.readClaudeOAuthToken()
        } catch KeychainError.itemNotFound {
            state = .missingToken
            return
        } catch {
            state = .error("Couldn't read Keychain: \(error)")
            return
        }

        do {
            let snapshot = try await api.fetchUsage(token: token)
            state = .ok(snapshot)
            return
        } catch let apiError as AnthropicAPIError {
            // Fall through to local estimate.
            await fallbackToEstimate(reason: describe(apiError))
        } catch {
            await fallbackToEstimate(reason: error.localizedDescription)
        }
    }

    private func fallbackToEstimate(reason: String) async {
        let now = clock()
        let agg = aggregator.aggregateRollingWindow(
            endingAt: now,
            duration: 5 * 3600,
            rootDirectory: projectsDirectory
        )
        let snapshot = UsageSnapshot(
            fiveHour: nil,
            sevenDay: nil,
            source: .estimated,
            capturedAt: now,
            estimatedFiveHourTokens: agg.totalTokens
        )
        state = .estimated(snapshot, underlyingMessage: reason)
    }

    private func describe(_ e: AnthropicAPIError) -> String {
        switch e {
        case .unauthorized: return "Anthropic API rejected the token (401)."
        case .rateLimited(let retry):
            if let r = retry { return "Rate limited. Retry in \(Int(r))s." }
            return "Rate limited."
        case .server(let code): return "Anthropic API server error (\(code))."
        case .malformedResponse: return "Anthropic API response shape changed."
        case .transport(let m): return "Network error: \(m)"
        }
    }

    // MARK: - Polling loop

    private func scheduleLoop() {
        loopTask?.cancel()
        guard !isPaused else { return }

        let interval = isPopoverOpen ? foregroundInterval : backgroundInterval
        loopTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                if Task.isCancelled { return }
                await self?.refresh()
            }
        }
    }

    // MARK: - Sleep / wake

    private func installSleepObservers() {
        guard !observersInstalled else { return }
        observersInstalled = true
        #if canImport(AppKit)
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleSleep() }
        }
        center.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleWake() }
        }
        #endif
    }

    private func handleSleep() {
        isPaused = true
        loopTask?.cancel()
    }

    private func handleWake() {
        isPaused = false
        scheduleLoop()
        Task { await self.refresh() }
    }
}
