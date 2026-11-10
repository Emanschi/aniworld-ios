import Foundation
import Network
import Observation

/// Finds Google Cast receivers (Chromecast, Google TV, Nest, ...) in the local network via Bonjour.
@MainActor
@Observable
final class CastDiscovery {
    struct Device: Identifiable, Hashable {
        /// TXT "id", or the Bonjour service name as fallback.
        let id: String
        /// TXT "fn" (friendly name), or the Bonjour service name as fallback.
        let name: String
        /// TXT "md" (model name), e.g. "Chromecast".
        let model: String?
        let endpoint: NWEndpoint
    }

    private(set) var devices: [Device] = []
    private(set) var isSearching = false

    @ObservationIgnored private var browser: NWBrowser?

    /// Starts browsing for `_googlecast._tcp`. Calling it while already running does nothing.
    func start() {
        guard browser == nil else { return }

        let parameters = NWParameters()
        parameters.includePeerToPeer = false
        let newBrowser = NWBrowser(
            for: .bonjourWithTXTRecord(type: "_googlecast._tcp", domain: "local."),
            using: parameters
        )

        newBrowser.browseResultsChangedHandler = { [weak self] results, _ in
            let found = CastDiscovery.makeDevices(from: results)
            MainActor.assumeIsolated {
                self?.devices = found
            }
        }
        newBrowser.stateUpdateHandler = { [weak self, weak newBrowser] state in
            MainActor.assumeIsolated {
                guard let self, let newBrowser, self.browser === newBrowser else { return }
                switch state {
                case .ready:
                    self.isSearching = true
                case .failed, .cancelled:
                    self.isSearching = false
                    self.browser = nil
                default:
                    break
                }
            }
        }

        browser = newBrowser
        isSearching = true
        // The main queue lets the handlers above use MainActor.assumeIsolated.
        newBrowser.start(queue: .main)
    }

    func stop() {
        browser?.cancel()
        browser = nil
        isSearching = false
    }

    /// Converts browse results into devices. One physical device can show up several times
    /// (IPv4/IPv6, several interfaces), so results are de-duplicated by id.
    nonisolated private static func makeDevices(from results: Set<NWBrowser.Result>) -> [Device] {
        var byID: [String: Device] = [:]
        for result in results {
            var serviceName: String?
            if case let .service(name, _, _, _) = result.endpoint {
                serviceName = name
            }
            var txtID: String?
            var friendlyName: String?
            var model: String?
            if case let .bonjour(record) = result.metadata {
                txtID = record["id"]
                friendlyName = record["fn"]
                model = record["md"]
            }
            guard let id = nonEmpty(txtID) ?? nonEmpty(serviceName) else { continue }
            let name = nonEmpty(friendlyName) ?? nonEmpty(serviceName) ?? id
            if byID[id] == nil {
                byID[id] = Device(id: id, name: name, model: nonEmpty(model), endpoint: result.endpoint)
            }
        }
        return byID.values.sorted {
            let order = $0.name.localizedCaseInsensitiveCompare($1.name)
            return order == .orderedSame ? $0.id < $1.id : order == .orderedAscending
        }
    }

    nonisolated private static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }
}
