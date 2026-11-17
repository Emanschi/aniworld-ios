import Foundation
import Network
import Observation

/// Observable view on the current network path (Wi-Fi / mobile data / Low Data Mode).
/// One shared instance lives in `AppEnvironment`; views read it via `@Environment(NetworkStatus.self)`.
@MainActor
@Observable
final class NetworkStatus {
    /// False until the first path update arrived; nothing is claimed about the network before that.
    private(set) var isKnown = false
    private(set) var isOnline = true
    /// Connected over the cellular interface (and not over Wi-Fi / Ethernet).
    private(set) var isCellular = false
    /// The system flags the connection as costly (mobile data, but also a personal hotspot).
    private(set) var isExpensive = false
    /// Low Data Mode is active for the current connection.
    private(set) var isConstrained = false

    /// Mobile data or another metered connection (e.g. personal hotspot): streaming should be careful.
    var usesMobileData: Bool { isOnline && (isCellular || isExpensive) }

    @ObservationIgnored private let monitor = NWPathMonitor()
    @ObservationIgnored private let queue = DispatchQueue(label: "NetworkStatus")

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            let wifi = path.usesInterfaceType(.wifi) || path.usesInterfaceType(.wiredEthernet)
            let cellular = online && path.usesInterfaceType(.cellular) && !wifi
            let expensive = path.isExpensive
            let constrained = path.isConstrained
            Task { @MainActor [weak self] in
                self?.apply(online: online, cellular: cellular, expensive: expensive, constrained: constrained)
            }
        }
        monitor.start(queue: queue)
    }

    private func apply(online: Bool, cellular: Bool, expensive: Bool, constrained: Bool) {
        isKnown = true
        if isOnline != online { isOnline = online }
        if isCellular != cellular { isCellular = cellular }
        if isExpensive != expensive { isExpensive = expensive }
        if isConstrained != constrained { isConstrained = constrained }
    }
}
