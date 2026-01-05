# Epithet for Mac - Application Specification

## Overview

Epithet for Mac is a macOS menubar application that manages multiple epithet broker instances. Each broker connects to an epithet CA server to provide SSH certificate authentication.

## Core Requirements

### Bundled Epithet Binary

The app bundles the `epithet` CLI binary inside the application bundle. The binary is fetched from GitHub releases at build time.

**Bundle Location**: `EpithetAgent.app/Contents/Resources/epithet`

**Build Process**:
1. At build time, fetch the latest release from `github.com/epithet-ssh/epithet/releases`
2. Download the macOS arm64 binary (darwin-arm64)
3. Place the binary in `Resources/` for bundling
4. The Makefile handles this automatically before compiling

**Platform Support**: Apple Silicon (arm64) only. Intel Macs not supported.

**Runtime Behavior**:
- App uses the bundled binary at `Bundle.main.resourcePath/epithet`
- No user configuration needed for binary path
- App version effectively pins the epithet version

### Multi-Broker Support

The app supports configuring and running multiple independent epithet broker instances. Each broker:
- Has its own configuration (CA URL, auth settings, etc.)
- Runs as a separate process
- Has its own runtime state directory
- Can be started/stopped independently

### Storage Locations

**Configuration Storage**: App's runtime state directory
- `~/Library/Application Support/EpithetAgent/brokers/`
- NOT `~/.epithet/` (that's for the CLI tool)

**Runtime State**: Per-broker directories
- `~/Library/Application Support/EpithetAgent/brokers/<broker-id>/`
- Contains: broker socket, agent sockets, ssh-config fragment

### SSH Config Integration

The app manages SSH config integration via `~/.ssh/config`:
- Adds an `Include` directive pointing to app-managed config
- Include path: `~/Library/Application Support/EpithetAgent/ssh-config.conf`
- The app-managed config file contains `Match exec` blocks for each running broker

---

## User Interface

### Menubar Menu

The menubar displays a key icon. The menu contains:

```
[icon] Broker Name 1          (running indicator)
[icon] Broker Name 2          (stopped indicator)
---
Inspect...
Configure Brokers...
---
Quit
```

**Broker Status Icons**:
- Running: Green dot or checkmark
- Stopped: Gray dot or dash
- Error: Red dot or warning icon

**Broker Menu Item Behavior**:
- Click toggles the broker state (start if stopped, stop if running)
- Running brokers show as enabled/active
- Stopped brokers show as dimmed/inactive

### Configuration Window

Split-view layout similar to macOS System Settings:

```
+------------------+----------------------------------------+
|                  |                                        |
|  Broker List     |  Selected Broker Configuration         |
|                  |                                        |
|  [+] [-]         |  Name: [________________]              |
|                  |                                        |
|  > Work CA       |  CA URL: [________________]            |
|    Personal CA   |                                        |
|                  |  Authentication:                       |
|                  |  ( ) Auto-discover from CA             |
|                  |  ( ) OIDC                              |
|                  |      Issuer: [________________]        |
|                  |      Client ID: [________________]     |
|                  |      Client Secret: [________________] |
|                  |  ( ) Custom command                    |
|                  |      Command: [________________]       |
|                  |                                        |
|                  |  Advanced:                             |
|                  |    CA Timeout: [15] seconds            |
|                  |    Cooldown:   [10] minutes            |
|                  |                                        |
|                  |  [Start on Login: checkbox]            |
|                  |                                        |
+------------------+----------------------------------------+
```

**Left Panel (Broker List)**:
- List of configured brokers
- Add (+) and Remove (-) buttons
- Selection highlights the broker for editing
- Visual indicator of running/stopped state

**Right Panel (Broker Configuration)**:
- Shows configuration for selected broker
- Changes save automatically or on blur
- Validation feedback inline

### Inspect Window

Displays runtime state from `epithet agent inspect` for each running broker. Tabbed interface with one tab per broker.

```
+------------------------------------------------------------------+
| [Work CA] [Personal CA]                                          |
+------------------------------------------------------------------+
|                                                                  |
|  Socket: ~/.epithet/run/abc123/broker.sock                       |
|                                                                  |
|  Discovery Patterns:                                             |
|    *.work.example.com                                            |
|    prod-*.internal                                               |
|                                                                  |
|  Active Agents:                                                  |
|  +------------------+---------------------------+-------------+  |
|  | Connection Hash  | Host                      | Expires     |  |
|  +------------------+---------------------------+-------------+  |
|  | a1b2c3d4         | server1.work.example.com  | in 2h 15m   |  |
|  | e5f6g7h8         | prod-db.internal          | in 45m      |  |
|  +------------------+---------------------------+-------------+  |
|                                                                  |
|  Cached Certificates:                                            |
|  +---------------------------+------------+---------------------+ |
|  | Host Pattern              | Principal  | Expires             | |
|  +---------------------------+------------+---------------------+ |
|  | *.work.example.com        | alice      | 2024-01-15 14:30    | |
|  | prod-*                    | alice      | 2024-01-15 12:00    | |
|  +---------------------------+------------+---------------------+ |
|                                                                  |
|                                          [Refresh]               |
+------------------------------------------------------------------+
```

**Behavior**:
- Opens via "Inspect..." menu item
- Only shows tabs for running brokers
- Disabled/empty state if no brokers are running
- Refresh button updates the inspect data
- Auto-refresh optional (every 30s when window is visible)
- Tabs for stopped brokers are hidden or show "Not Running" state

**Data Source**: Runs `<bundled-epithet> agent inspect --broker <socket-path>` or uses RPC directly via the broker's Unix socket.

---

## Broker Configuration Model

### Configuration Properties

Each broker configuration contains:

| Property | Type | Required | Default | Description |
|----------|------|----------|---------|-------------|
| `name` | String | Yes | - | Display name for the broker (must be unique) |
| `caURL` | String | Yes | - | CA server URL |
| `authMethod` | Enum | Yes | `.autoDiscover` | Authentication method |
| `oidcIssuer` | String | Conditional | - | OIDC issuer URL (if authMethod == .oidc) |
| `oidcClientID` | String | Conditional | - | OIDC client ID (if authMethod == .oidc) |
| `oidcClientSecret` | String | No | - | OIDC client secret (optional) |
| `authCommand` | String | Conditional | - | Custom auth command (if authMethod == .command) |
| `caTimeout` | Duration | No | 15s | Per-request timeout |
| `caCooldown` | Duration | No | 10m | Circuit breaker cooldown |
| `startOnLogin` | Bool | No | false | Auto-start when app launches |

### Authentication Methods

```swift
enum AuthMethod: String, Codable {
    case autoDiscover  // Let broker discover auth from CA bootstrap
    case oidc          // Use OIDC with provided issuer/client
    case command       // Use custom auth command
}
```

### Data Types

Configuration stored as JSON:

```json
{
  "brokers": [
    {
      "name": "Work CA",
      "caURL": "https://ca.work.example.com",
      "authMethod": "oidc",
      "oidcIssuer": "https://accounts.google.com",
      "oidcClientID": "123456.apps.googleusercontent.com",
      "oidcClientSecret": null,
      "caTimeout": 15,
      "caCooldown": 600,
      "startOnLogin": true
    }
  ]
}
```

The broker name serves as the primary identifier within the app. The broker itself generates a config-derived hash for its runtime directory paths.

---

## Runtime Behavior

### Broker Lifecycle

**Starting a Broker**:
1. Build command line arguments from configuration
2. Launch `epithet agent` process with arguments
3. Broker creates its own runtime directory based on config hash
4. Monitor process for startup success/failure
5. Update SSH config to include this broker's Match block
6. Update menubar status

**Stopping a Broker**:
1. Send SIGTERM to broker process
2. Wait for graceful shutdown (with timeout)
3. Remove broker's Match block from SSH config
4. Update menubar status

**Command Line Construction**:

The app invokes the bundled binary at `Bundle.main.resourcePath/epithet`:

```bash
<bundled-epithet> agent \
  --ca-url <caURL> \
  --ca-timeout <caTimeout>s \
  --ca-cooldown <caCooldown>m \
  [--auth "<authCommand>"]  # if authMethod == .command or .oidc
```

For OIDC auth method, construct (using bundled binary path):
```bash
--auth "<bundled-epithet> auth oidc --issuer <oidcIssuer> --client-id <oidcClientID> [--client-secret <oidcClientSecret>]"
```

For auto-discover, omit `--auth` flag entirely.

### SSH Config Management

**App-managed config file**: `~/Library/Application Support/EpithetAgent/ssh-config.conf`

Contents (regenerated when brokers start/stop):
```
# Managed by Epithet for Mac - Do not edit manually

# Broker: Work CA
Match exec "<bundled-epithet> match --host %h --port %p --user %r --hash %C --broker <broker-runtime-dir>/broker.sock"
    IdentityAgent <broker-runtime-dir>/agents/%C.sock

# Broker: Personal CA
Match exec "<bundled-epithet> match --host %h --port %p --user %r --hash %C --broker <broker-runtime-dir>/broker.sock"
    IdentityAgent <broker-runtime-dir>/agents/%C.sock
```

Notes:
- `<bundled-epithet>` is the full path to the bundled binary (e.g., `/Applications/EpithetAgent.app/Contents/Resources/epithet`)
- The broker runtime directory path is determined by the broker itself based on a hash of its configuration
- The app discovers the runtime path after the broker starts

**SSH Config Include Setup**:

On first launch, ensure `~/.ssh/config` contains:
```
Include ~/Library/Application Support/EpithetAgent/ssh-config.conf
```

The include should be at the top of the file (before other Host/Match blocks).

### Process Management

**Process Tracking**:
- Store PID of each running broker
- Monitor processes for unexpected termination
- Restart brokers marked as `startOnLogin` if they crash (with backoff)

**App Lifecycle**:
- On app launch: Start all brokers with `startOnLogin == true`
- On app quit: Stop all running brokers gracefully
- On system sleep: Keep brokers running (they handle reconnection)
- On system wake: Verify brokers are still running

---

## File System Layout

```
~/Library/Application Support/EpithetAgent/
├── config.json                    # Broker configurations (app-managed)
└── ssh-config.conf                # Generated SSH config (Include'd by ~/.ssh/config)

~/.epithet/run/                    # Broker runtime state (broker-managed)
└── <config-hash>/                 # Generated by broker from its config
    ├── broker.sock                # Broker RPC socket
    ├── agents/                    # Per-connection agent sockets
    │   └── <connection-hash>.sock
    └── ssh-config.conf            # Broker's SSH config fragment
```

Note: The broker manages its own runtime directory under `~/.epithet/run/`. The app only manages its configuration file and the SSH config integration.

---

## Error Handling

### Configuration Validation

**On Save**:
- CA URL must be valid HTTPS URL
- Name must be non-empty and unique
- OIDC fields required when authMethod == .oidc
- Command required when authMethod == .command

**On Start**:
- Verify epithet binary exists and is executable
- Verify CA URL is reachable (optional, with timeout)
- Display error in UI if broker fails to start

### Runtime Errors

**Broker Crash**:
- Detect via process monitoring
- Update menubar status to error state
- Log error details
- Optionally notify user
- Auto-restart with exponential backoff (if startOnLogin)

**SSH Config Conflicts**:
- Warn if Include directive cannot be added
- Provide manual instructions if ~/.ssh/config is read-only

---

## Future Considerations

### Not In Scope (v1)

- Multiple CA URLs per broker (failover)
- Manual certificate refresh
- Proxy jump configuration
- Per-broker log viewing
- Import/export configurations

### Potential v2 Features

- Status bar showing active connections
- Certificate expiry notifications
- Broker health dashboard
- Configuration sync via iCloud
- Touch ID integration for auth

---

## Implementation Notes

### Build: Fetching Epithet Binary

The Makefile fetches the epithet binary from GitHub releases before building:

```makefile
EPITHET_REPO := epithet-ssh/epithet

Resources/epithet:
	@echo "Fetching latest epithet release..."
	@mkdir -p Resources
	@curl -sL "https://api.github.com/repos/$(EPITHET_REPO)/releases/latest" \
		| grep -o '"browser_download_url": *"[^"]*darwin_arm64[^"]*"' \
		| head -1 \
		| cut -d'"' -f4 \
		| xargs curl -sL -o Resources/epithet.tar.gz
	@tar -xzf Resources/epithet.tar.gz -C Resources
	@rm Resources/epithet.tar.gz
	@chmod +x Resources/epithet

build: Resources/epithet
	swift build

bundle: Resources/epithet
	# ... bundle creation includes Resources/epithet
```

### Swift Types

```swift
struct BrokerConfig: Codable, Identifiable, Hashable {
    var id: String { name }  // Name is the unique identifier
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
}

enum AuthMethod: String, Codable {
    case autoDiscover
    case oidc
    case command
}

enum BrokerState {
    case stopped
    case starting
    case running(pid: pid_t, runtimeDir: String)  // runtimeDir discovered from broker
    case error(String)
}
```

### Key Classes

- `BrokerManager`: Manages broker lifecycle (start/stop/monitor)
- `BrokerConfigStore`: Persists and loads broker configurations
- `SSHConfigManager`: Manages ~/.ssh/config integration
- `ConfigurationWindowController`: Configuration UI (split-view broker list/editor)
- `InspectWindowController`: Inspect UI (tabbed broker status viewer)
- `StatusBarController`: Menubar UI (existing, needs update)
