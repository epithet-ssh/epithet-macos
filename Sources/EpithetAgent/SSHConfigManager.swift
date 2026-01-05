import Foundation

class SSHConfigManager {
    static let shared = SSHConfigManager()

    private let fileManager = FileManager.default
    private let configStore = BrokerConfigStore.shared

    private var sshConfigPath: String {
        (NSHomeDirectory() as NSString).appendingPathComponent(".ssh/config")
    }

    private var appSSHConfigPath: String {
        configStore.appSupportDirectory.appendingPathComponent("ssh-config.conf").path
    }

    private let includeMarker = "# Epithet Agent Include"
    private let configHeader = "# Managed by Epithet for Mac - Do not edit manually\n"

    private init() {}

    func setup() {
        ensureSSHDirectoryExists()
        ensureIncludeDirective()
        updateSSHConfig()
    }

    private func ensureSSHDirectoryExists() {
        let sshDir = (NSHomeDirectory() as NSString).appendingPathComponent(".ssh")
        if !fileManager.fileExists(atPath: sshDir) {
            try? fileManager.createDirectory(atPath: sshDir, withIntermediateDirectories: true)
            // Set proper permissions for .ssh directory
            try? fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: sshDir)
        }
    }

    func ensureIncludeDirective() {
        let includeLine = "Include \(appSSHConfigPath)"

        // Read existing config or create empty
        var config: String
        if fileManager.fileExists(atPath: sshConfigPath) {
            config = (try? String(contentsOfFile: sshConfigPath, encoding: .utf8)) ?? ""
        } else {
            config = ""
        }

        // Check if include already exists
        if config.contains(includeLine) || config.contains(appSSHConfigPath) {
            return
        }

        // Add include at the top of the file
        let newContent = "\(includeMarker)\n\(includeLine)\n\n\(config)"

        do {
            try newContent.write(toFile: sshConfigPath, atomically: true, encoding: .utf8)
            // Ensure proper permissions
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: sshConfigPath)
        } catch {
            print("Failed to update SSH config: \(error)")
        }
    }

    func updateSSHConfig() {
        let brokerManager = BrokerManager.shared
        let epithetPath = brokerManager.epithetBinaryPath

        var configContent = configHeader
        configContent += "\n"

        // Add Match blocks for each running broker
        for broker in configStore.brokers {
            let state = brokerManager.state(for: broker.name)

            guard case .running(_, let runtimeDir) = state else {
                continue
            }

            let socketPath = (runtimeDir as NSString).appendingPathComponent("broker.sock")
            let agentsDir = (runtimeDir as NSString).appendingPathComponent("agents")

            configContent += "# Broker: \(broker.name)\n"
            configContent += "Match exec \"\(epithetPath) match --host %h --port %p --user %r --hash %C --broker \(socketPath)\"\n"
            configContent += "    IdentityAgent \(agentsDir)/%C.sock\n"
            configContent += "\n"
        }

        do {
            try configContent.write(toFile: appSSHConfigPath, atomically: true, encoding: .utf8)
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: appSSHConfigPath)
        } catch {
            print("Failed to write app SSH config: \(error)")
        }
    }

    func removeIncludeDirective() {
        guard fileManager.fileExists(atPath: sshConfigPath) else { return }

        do {
            var config = try String(contentsOfFile: sshConfigPath, encoding: .utf8)

            // Remove the include marker and include line
            let includeLine = "Include \(appSSHConfigPath)"
            config = config.replacingOccurrences(of: "\(includeMarker)\n\(includeLine)\n\n", with: "")
            config = config.replacingOccurrences(of: "\(includeMarker)\n\(includeLine)\n", with: "")
            config = config.replacingOccurrences(of: "\(includeLine)\n", with: "")

            try config.write(toFile: sshConfigPath, atomically: true, encoding: .utf8)
        } catch {
            print("Failed to remove include directive: \(error)")
        }
    }
}
