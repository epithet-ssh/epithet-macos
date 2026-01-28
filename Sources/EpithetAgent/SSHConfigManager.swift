import Foundation

class SSHConfigManager {
    static let shared = SSHConfigManager()

    private let fileManager = FileManager.default

    private var sshConfigPath: String {
        (NSHomeDirectory() as NSString).appendingPathComponent(".ssh/config")
    }

    // Standard epithet Include pattern - brokers write their own ssh-config.conf files.
    private let includePattern = "Include ~/.epithet/run/*/ssh-config.conf"

    private init() {}

    func setup() {
        ensureSSHDirectoryExists()
        ensureIncludeDirective()
    }

    private func ensureSSHDirectoryExists() {
        let sshDir = (NSHomeDirectory() as NSString).appendingPathComponent(".ssh")
        if !fileManager.fileExists(atPath: sshDir) {
            try? fileManager.createDirectory(atPath: sshDir, withIntermediateDirectories: true)
            // Set proper permissions for .ssh directory.
            try? fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: sshDir)
        }
    }

    func ensureIncludeDirective() {
        // Read existing config or create empty.
        var config: String
        if fileManager.fileExists(atPath: sshConfigPath) {
            config = (try? String(contentsOfFile: sshConfigPath, encoding: .utf8)) ?? ""
        } else {
            config = ""
        }

        // Check if include pattern already exists.
        if config.contains(includePattern) {
            return
        }

        // Append include at the end of the file.
        var newContent = config
        if !newContent.isEmpty && !newContent.hasSuffix("\n") {
            newContent += "\n"
        }
        if !newContent.isEmpty && !newContent.hasSuffix("\n\n") {
            newContent += "\n"
        }
        newContent += includePattern + "\n"

        do {
            try newContent.write(toFile: sshConfigPath, atomically: true, encoding: .utf8)
            // Ensure proper permissions.
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: sshConfigPath)
        } catch {
            print("Failed to update SSH config: \(error)")
        }
    }
}
