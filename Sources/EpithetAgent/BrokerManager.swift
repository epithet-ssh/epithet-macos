import Foundation
import AppKit

class BrokerManager {
    static let shared = BrokerManager()

    private var processes: [String: Process] = [:]  // keyed by broker name
    private var states: [String: BrokerState] = [:]  // keyed by broker name
    private var logs: [String: String] = [:]  // keyed by broker name
    private var logHandles: [String: (stdout: FileHandle, stderr: FileHandle)] = [:]
    private let configStore = BrokerConfigStore.shared

    var onStateChange: ((String, BrokerState) -> Void)?
    var onLogUpdate: ((String) -> Void)?  // called with broker name when logs update

    private init() {}

    var epithetBinaryPath: String {
        // When running from bundle, use bundled binary
        if let resourcePath = Bundle.main.resourcePath {
            let bundledPath = (resourcePath as NSString).appendingPathComponent("epithet")
            if FileManager.default.fileExists(atPath: bundledPath) {
                return bundledPath
            }
        }
        // Fallback for development: use Resources/epithet relative to executable
        let executablePath = Bundle.main.executablePath ?? ""
        let executableDir = (executablePath as NSString).deletingLastPathComponent
        let devPath = (executableDir as NSString).appendingPathComponent("../../Resources/epithet")
        if FileManager.default.fileExists(atPath: devPath) {
            return (devPath as NSString).standardizingPath
        }
        // Last resort: check current directory
        return "./Resources/epithet"
    }

    func state(for brokerName: String) -> BrokerState {
        states[brokerName] ?? .stopped
    }

    func getLogs(for brokerName: String) -> String {
        logs[brokerName] ?? ""
    }

    func clearLogs(for brokerName: String) {
        logs[brokerName] = ""
    }

    func start(broker: BrokerConfig) {
        guard states[broker.name]?.isRunning != true else {
            print("Broker \(broker.name) is already running")
            return
        }

        setState(.starting, for: broker.name)
        logs[broker.name] = ""  // Clear previous logs

        let process = Process()
        process.executableURL = URL(fileURLWithPath: epithetBinaryPath)
        process.arguments = buildArguments(for: broker)

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        // Capture stdout
        outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if !data.isEmpty, let str = String(data: data, encoding: .utf8) {
                DispatchQueue.main.async {
                    self?.appendLog(str, for: broker.name)
                }
            }
        }

        // Capture stderr
        errorPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if !data.isEmpty, let str = String(data: data, encoding: .utf8) {
                DispatchQueue.main.async {
                    self?.appendLog(str, for: broker.name)
                }
            }
        }

        logHandles[broker.name] = (stdout: outputPipe.fileHandleForReading, stderr: errorPipe.fileHandleForReading)

        process.terminationHandler = { [weak self] proc in
            DispatchQueue.main.async {
                self?.handleTermination(broker: broker, process: proc)
            }
        }

        do {
            try process.run()
            processes[broker.name] = process
            let urlsDescription = broker.caURLs.joined(separator: ", ")
            appendLog("Starting broker with CA URLs: \(urlsDescription)\n", for: broker.name)

            // Give the broker a moment to start, then discover runtime dir
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.discoverRuntimeDir(for: broker, process: process)
            }
        } catch {
            appendLog("Failed to start: \(error.localizedDescription)\n", for: broker.name)
            setState(.error("Failed to start: \(error.localizedDescription)"), for: broker.name)
        }
    }

    private func appendLog(_ text: String, for brokerName: String) {
        if logs[brokerName] == nil {
            logs[brokerName] = ""
        }
        logs[brokerName]! += text

        // Limit log size to ~100KB
        if let log = logs[brokerName], log.count > 100_000 {
            logs[brokerName] = String(log.suffix(80_000))
        }

        onLogUpdate?(brokerName)
    }

    func stop(brokerName: String) {
        guard let process = processes[brokerName], process.isRunning else {
            setState(.stopped, for: brokerName)
            return
        }

        process.terminate()
        // State will be updated in termination handler
    }

    func stopAll() {
        for name in processes.keys {
            stop(brokerName: name)
        }
    }

    func startAutoStartBrokers() {
        for broker in configStore.brokers where broker.startOnLogin {
            start(broker: broker)
        }
    }

    func toggle(brokerName: String) {
        if let state = states[brokerName], state.isRunning {
            stop(brokerName: brokerName)
        } else if let broker = configStore.broker(named: brokerName) {
            start(broker: broker)
        }
    }

    func inspect(brokerName: String, completion: @escaping (String?) -> Void) {
        guard case .running(_, let runtimeDir) = states[brokerName] else {
            completion(nil)
            return
        }

        let socketPath = (runtimeDir as NSString).appendingPathComponent("broker.sock")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: epithetBinaryPath)
        process.arguments = ["agent", "inspect", "--broker", socketPath]

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()

            let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)
            completion(output)
        } catch {
            completion(nil)
        }
    }

    private func buildArguments(for broker: BrokerConfig) -> [String] {
        var args = ["agent"]

        // Add verbosity flags
        args.append(contentsOf: broker.verbosity.flags)

        for url in broker.caURLs {
            args.append(contentsOf: ["--ca-url", url])
        }
        args.append(contentsOf: ["--ca-timeout", "\(broker.caTimeout)s"])
        args.append(contentsOf: ["--ca-cooldown", "\(broker.caCooldown)s"])

        switch broker.authMethod {
        case .autoDiscover:
            break  // No --auth flag
        case .oidc:
            var authCmd = "\(epithetBinaryPath) auth oidc"
            if let issuer = broker.oidcIssuer {
                authCmd += " --issuer \(issuer)"
            }
            if let clientID = broker.oidcClientID {
                authCmd += " --client-id \(clientID)"
            }
            if let clientSecret = broker.oidcClientSecret, !clientSecret.isEmpty {
                authCmd += " --client-secret \(clientSecret)"
            }
            args.append(contentsOf: ["--auth", authCmd])
        case .command:
            if let cmd = broker.authCommand {
                args.append(contentsOf: ["--auth", cmd])
            }
        }

        return args
    }

    private func discoverRuntimeDir(for broker: BrokerConfig, process: Process) {
        guard process.isRunning else {
            // Process already terminated
            return
        }

        // The broker creates its runtime dir at ~/.epithet/run/<hash>/
        // We need to find it. For now, we'll scan the directory.
        let epithetRunDir = (NSHomeDirectory() as NSString).appendingPathComponent(".epithet/run")

        do {
            let contents = try FileManager.default.contentsOfDirectory(atPath: epithetRunDir)
            // Find the most recently created directory with a broker.sock
            var foundDir: String?
            var latestDate: Date?

            for dir in contents {
                let fullPath = (epithetRunDir as NSString).appendingPathComponent(dir)
                let socketPath = (fullPath as NSString).appendingPathComponent("broker.sock")

                if FileManager.default.fileExists(atPath: socketPath) {
                    let attrs = try? FileManager.default.attributesOfItem(atPath: fullPath)
                    if let created = attrs?[.creationDate] as? Date {
                        if latestDate == nil || created > latestDate! {
                            latestDate = created
                            foundDir = fullPath
                        }
                    } else {
                        foundDir = fullPath
                    }
                }
            }

            if let runtimeDir = foundDir {
                setState(.running(pid: process.processIdentifier, runtimeDir: runtimeDir), for: broker.name)
            } else {
                // Keep checking for a bit
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                    if process.isRunning {
                        self?.discoverRuntimeDir(for: broker, process: process)
                    }
                }
            }
        } catch {
            // Directory doesn't exist yet, retry
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                if process.isRunning {
                    self?.discoverRuntimeDir(for: broker, process: process)
                }
            }
        }
    }

    private func handleTermination(broker: BrokerConfig, process: Process) {
        processes.removeValue(forKey: broker.name)

        // Clean up log handles
        if let handles = logHandles[broker.name] {
            handles.stdout.readabilityHandler = nil
            handles.stderr.readabilityHandler = nil
        }
        logHandles.removeValue(forKey: broker.name)

        if process.terminationStatus == 0 {
            appendLog("\nBroker stopped.\n", for: broker.name)
            setState(.stopped, for: broker.name)
        } else {
            appendLog("\nBroker exited with code \(process.terminationStatus)\n", for: broker.name)
            setState(.error("Exited with code \(process.terminationStatus)"), for: broker.name)
        }
    }

    private func setState(_ state: BrokerState, for brokerName: String) {
        states[brokerName] = state
        DispatchQueue.main.async { [weak self] in
            self?.onStateChange?(brokerName, state)
        }
    }

    func runningBrokers() -> [(name: String, state: BrokerState)] {
        states.compactMap { name, state in
            state.isRunning ? (name, state) : nil
        }
    }
}
