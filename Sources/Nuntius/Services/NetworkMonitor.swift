import Foundation
import Network
import os

/// Monitors network connectivity status using NWPathMonitor.
@Observable
@MainActor
final class NetworkMonitor {
    static let shared = NetworkMonitor()

    /// Whether the device currently has network connectivity
    private(set) var isConnected: Bool = true

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.chrismatix.nuntius.networkMonitor")
    private let logger = Logger(subsystem: "com.chrismatix.nuntius", category: "NetworkMonitor")
    private var isMonitoring = false

    private init() {
        // Check initial state synchronously
        let path = monitor.currentPath
        isConnected = path.status == .satisfied
    }

    /// Starts monitoring network connectivity changes
    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true

        monitor.pathUpdateHandler = { [weak self] path in
            let connected = path.status == .satisfied
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.isConnected != connected {
                    self.isConnected = connected
                    self.logger.info("Network connectivity changed: \(connected ? "connected" : "disconnected")")
                }
            }
        }

        monitor.start(queue: queue)
        logger.info("Network monitoring started")
    }

    /// Stops monitoring network connectivity changes
    func stopMonitoring() {
        guard isMonitoring else { return }
        isMonitoring = false
        monitor.cancel()
        logger.info("Network monitoring stopped")
    }
}
