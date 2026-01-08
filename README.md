# Epithet for Mac

A macOS menubar application for managing [Epithet](https://github.com/epithet-ssh/epithet) SSH certificate broker agents.

## Features

- **Menubar Integration** - Lives in your menubar, no dock icon clutter
- **Multiple Brokers** - Configure and manage multiple broker instances
- **Status Indicators** - See at a glance which brokers are running (green), starting (yellow), stopped, or errored (red)
- **One-Click Toggle** - Start/stop brokers directly from the menubar
- **SSH Config Integration** - Automatically configures SSH to use your brokers
- **Live Logs** - View broker output in real-time via the Inspect window
- **Launch at Login** - Optionally start the app when you log in
- **Auto-Start Brokers** - Configure brokers to start automatically when the app launches

## Requirements

- macOS 13.0 (Ventura) or later
- Apple Silicon (arm64)

## Installation

### From Source

```bash
# Clone the repository
git clone https://github.com/epithet-ssh/epithet-macos.git
cd epithet-macos

# Build and install to /Applications
make install
```

The build process automatically fetches the latest `epithet` binary from GitHub releases.

### Development

```bash
make build      # Build debug version
make run        # Build and run
make bundle     # Create .app bundle for testing
```

## Usage

1. **Launch the app** - A key icon appears in your menubar
2. **Configure brokers** - Click the menubar icon > "Configure Brokers..."
3. **Add a broker** - Click "+" and fill in your CA URL and authentication settings
4. **Start brokers** - Click a broker name in the menubar to toggle it on/off

### Broker Configuration

Each broker can be configured with:

- **Name** - Display name for the broker
- **CA URL** - URL of your Epithet CA server
- **Authentication** - OIDC or Command-based authentication
- **Timeouts** - CA timeout and cooldown periods
- **Verbosity** - Log level (warn, info, debug, trace)
- **Start when app launches** - Auto-start this broker

### SSH Integration

The app automatically:
1. Creates an SSH config fragment at `~/Library/Application Support/EpithetAgent/ssh-config.conf`
2. Adds an `Include` directive to your `~/.ssh/config`

This enables seamless SSH certificate authentication through your configured brokers.

## Configuration Storage

- Broker configs: `~/Library/Application Support/EpithetAgent/config.json`
- Broker runtime data: `~/.epithet/<broker-hash>/`

## Releases

Releases are coordinated via the [packaging](https://github.com/epithet-ssh/packaging) repository, which orchestrates unified releases across all epithet-ssh projects.

## License

Licensed under the Apache License, Version 2.0. See [LICENSE-2.0.txt](LICENSE-2.0.txt) for details.
