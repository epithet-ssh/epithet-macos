import Foundation
import AppKit
import os

private let logger = Logger(subsystem: "dev.epithet.agent", category: "BrokerManager")

/// Creates a Logger for a specific broker's output.
private func brokerLogger(name: String) -> Logger {
    Logger(subsystem: "dev.epithet.agent", category: "Broker:\(name)")
}

/// Parses a log line from the epithet binary and extracts the level and message.
/// Format: "[ANSI]HH:MM:SS[ANSI] [ANSI]LVL[ANSI] message" where LVL is DBG/INF/WRN/ERR
private func parseLogLine(_ line: String) -> (level: OSLogType, message: String)? {
    // Strip ANSI escape codes: \x1B[...m
    let stripped = line.replacingOccurrences(
        of: "\\x1B\\[[0-9;]*m",
        with: "",
        options: .regularExpression
    )
    
    // Format after stripping: "HH:MM:SS LVL message..."
    // Find the level token after the timestamp.
    let parts = stripped.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
    guard parts.count >= 2 else { return nil }
    
    let levelStr = String(parts[1])
    let message = parts.count > 2 ? String(parts[2]) : ""
    
    let level: OSLogType
    switch levelStr {
    case "DBG":
        level = .debug
    case "INF":
        level = .info
    case "WRN":
        level = .default  // .warning doesn't exist, use .default
    case "ERR":
        level = .error
    default:
        // Not a standard log line, treat as info.
        return (.info, stripped)
    }
    
    return (level, message)
}

class BrokerManager {
    static let shared = BrokerManager()

    private var processes: [String: Process] = [:]  // keyed by broker name
    private var states: [String: BrokerState] = [:]  // keyed by broker name
    private var logs: [String: String] = [:]  // keyed by broker name
    private var logHandles: [String: (stdout: FileHandle, stderr: FileHandle)] = [:]
    private let configStore = BrokerConfigStore.shared

    var onStateChange: ((String, BrokerState) -> Void)?
    var onLogUpdate: ((String) -> Void)?  // called with broker name when logs update

    // Constants for log management
    private static let maxLogSize = 100_000
    private static let trimmedLogSize = 80_000

    // Constants for runtime directory discovery
    private static let initialDiscoveryDelay: TimeInterval = 0.5
    private static let retryDiscoveryDelay: TimeInterval = 1.0

    private init() {}

    var epithetBinaryPath: String {
        // When running from bundle, use bundled binary.
        if let resourcePath = Bundle.main.resourcePath {
            let bundledPath = (resourcePath as NSString).appendingPathComponent("epithet")
            if FileManager.default.fileExists(atPath: bundledPath) {
                return bundledPath
            }
        }
        // Fallback for development: use Resources/epithet relative to executable.
        let executablePath = Bundle.main.executablePath ?? ""
        let executableDir = (executablePath as NSString).deletingLastPathComponent
        let devPath = (executableDir as NSString).appendingPathComponent("../../Resources/epithet")
        if FileManager.default.fileExists(atPath: devPath) {
            return (devPath as NSString).standardizingPath
        }
        // When running from Xcode, try the source directory.
        // The executable is in DerivedData, but we can find the source via the project structure.
        #if DEBUG
        let sourceResourcesPath = URL(fileURLWithPath: #file)
            .deletingLastPathComponent()  // Sources/EpithetAgent
            .deletingLastPathComponent()  // Sources
            .deletingLastPathComponent()  // epithet-macos
            .appendingPathComponent("Resources/epithet")
            .path
        if FileManager.default.fileExists(atPath: sourceResourcesPath) {
            return sourceResourcesPath
        }
        #endif
        // Last resort: check current directory.
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
            logger.debug("Broker \(broker.name) is already running")
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
                DispatchQueue.main.async { [weak self] in
                    self?.appendLog(str, for: broker.name)
                }
            }
        }

        // Capture stderr
        errorPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if !data.isEmpty, let str = String(data: data, encoding: .utf8) {
                DispatchQueue.main.async { [weak self] in
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
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.initialDiscoveryDelay) { [weak self] in
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

        // Limit log size to prevent excessive memory usage
        if let log = logs[brokerName], log.count > Self.maxLogSize {
            logs[brokerName] = String(log.suffix(Self.trimmedLogSize))
        }

        // Forward each line to the unified logger.
        let brokerLog = brokerLogger(name: brokerName)
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let lineStr = String(line)
            if let (level, message) = parseLogLine(lineStr) {
                brokerLog.log(level: level, "\(message)")
            } else {
                brokerLog.info("\(lineStr)")
            }
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
                DispatchQueue.main.asyncAfter(deadline: .now() + Self.retryDiscoveryDelay) { [weak self] in
                    if process.isRunning {
                        self?.discoverRuntimeDir(for: broker, process: process)
                    }
                }
            }
        } catch {
            // Directory doesn't exist yet, retry
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.retryDiscoveryDelay) { [weak self] in
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
