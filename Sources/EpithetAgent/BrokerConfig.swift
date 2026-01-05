import Foundation

enum AuthMethod: String, Codable, CaseIterable {
    case autoDiscover
    case oidc
    case command

    var displayName: String {
        switch self {
        case .autoDiscover: return "Auto-discover from CA"
        case .oidc: return "OIDC"
        case .command: return "Custom Command"
        }
    }
}

enum Verbosity: Int, Codable, CaseIterable {
    case warn = 0      // default, no -v flags
    case info = 1      // -v
    case debug = 2     // -vv
    case trace = 3     // -vvv

    var displayName: String {
        switch self {
        case .warn: return "Warn (default)"
        case .info: return "Info (-v)"
        case .debug: return "Debug (-vv)"
        case .trace: return "Trace (-vvv)"
        }
    }

    var flags: [String] {
        switch self {
        case .warn: return []
        case .info: return ["-v"]
        case .debug: return ["-vv"]
        case .trace: return ["-vvv"]
        }
    }
}

struct BrokerConfig: Codable, Identifiable, Hashable {
    var name: String
    var caURL: String
    var authMethod: AuthMethod
    var oidcIssuer: String?
    var oidcClientID: String?
    var oidcClientSecret: String?
    var authCommand: String?
    var caTimeout: Int  // seconds
    var caCooldown: Int // seconds
    var startOnLogin: Bool
    var verbosity: Verbosity

    var id: String { name }

    init(
        name: String,
        caURL: String = "",
        authMethod: AuthMethod = .autoDiscover,
        oidcIssuer: String? = nil,
        oidcClientID: String? = nil,
        oidcClientSecret: String? = nil,
        authCommand: String? = nil,
        caTimeout: Int = 15,
        caCooldown: Int = 600,
        startOnLogin: Bool = true,
        verbosity: Verbosity = .info
    ) {
        self.name = name
        self.caURL = caURL
        self.authMethod = authMethod
        self.oidcIssuer = oidcIssuer
        self.oidcClientID = oidcClientID
        self.oidcClientSecret = oidcClientSecret
        self.authCommand = authCommand
        self.caTimeout = caTimeout
        self.caCooldown = caCooldown
        self.startOnLogin = startOnLogin
        self.verbosity = verbosity
    }

    func validate() -> [String] {
        var errors: [String] = []

        if name.trimmingCharacters(in: .whitespaces).isEmpty {
            errors.append("Name is required")
        }

        if caURL.trimmingCharacters(in: .whitespaces).isEmpty {
            errors.append("CA URL is required")
        } else if !caURL.lowercased().hasPrefix("https://") {
            errors.append("CA URL must be HTTPS")
        }

        switch authMethod {
        case .oidc:
            if oidcIssuer?.trimmingCharacters(in: .whitespaces).isEmpty ?? true {
                errors.append("OIDC Issuer is required")
            }
            if oidcClientID?.trimmingCharacters(in: .whitespaces).isEmpty ?? true {
                errors.append("OIDC Client ID is required")
            }
        case .command:
            if authCommand?.trimmingCharacters(in: .whitespaces).isEmpty ?? true {
                errors.append("Auth command is required")
            }
        case .autoDiscover:
            break
        }

        return errors
    }
}

enum BrokerState: Equatable {
    case stopped
    case starting
    case running(pid: pid_t, runtimeDir: String)
    case error(String)

    var isRunning: Bool {
        if case .running = self { return true }
        return false
    }

    var statusText: String {
        switch self {
        case .stopped: return "Stopped"
        case .starting: return "Starting..."
        case .running: return "Running"
        case .error(let msg): return "Error: \(msg)"
        }
    }
}
