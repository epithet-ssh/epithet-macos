import Foundation

class BrokerConfigStore {
    static let shared = BrokerConfigStore()

    private let fileManager = FileManager.default
    private var configFileURL: URL

    private(set) var brokers: [BrokerConfig] = []

    var onChange: (() -> Void)?

    private init() {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("EpithetAgent", isDirectory: true)

        // Ensure directory exists
        try? fileManager.createDirectory(at: appDir, withIntermediateDirectories: true)

        configFileURL = appDir.appendingPathComponent("config.json")
        load()
    }

    var appSupportDirectory: URL {
        configFileURL.deletingLastPathComponent()
    }

    func load() {
        guard fileManager.fileExists(atPath: configFileURL.path) else {
            brokers = []
            return
        }

        do {
            let data = try Data(contentsOf: configFileURL)
            let container = try JSONDecoder().decode(ConfigContainer.self, from: data)
            brokers = container.brokers
        } catch {
            print("Failed to load broker configs: \(error)")
            brokers = []
        }
    }

    func save() {
        do {
            let container = ConfigContainer(brokers: brokers)
            let data = try JSONEncoder().encode(container)
            try data.write(to: configFileURL, options: .atomic)
            onChange?()
        } catch {
            print("Failed to save broker configs: \(error)")
        }
    }

    func add(_ broker: BrokerConfig) {
        brokers.append(broker)
        save()
    }

    func update(_ broker: BrokerConfig) {
        if let index = brokers.firstIndex(where: { $0.name == broker.name }) {
            brokers[index] = broker
            save()
        }
    }

    func remove(at index: Int) {
        guard index >= 0 && index < brokers.count else { return }
        brokers.remove(at: index)
        save()
    }

    func remove(named name: String) {
        brokers.removeAll { $0.name == name }
        save()
    }

    func broker(named name: String) -> BrokerConfig? {
        brokers.first { $0.name == name }
    }

    func isNameUnique(_ name: String, excluding: String? = nil) -> Bool {
        !brokers.contains { $0.name == name && $0.name != excluding }
    }

    func generateUniqueName(base: String = "New Broker") -> String {
        if isNameUnique(base) { return base }
        var counter = 2
        while !isNameUnique("\(base) \(counter)") {
            counter += 1
        }
        return "\(base) \(counter)"
    }
}

private struct ConfigContainer: Codable {
    var brokers: [BrokerConfig]
}
