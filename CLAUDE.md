# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Epithet for Mac - A macOS menubar application to manage epithet SSH certificate broker agents. Built with Swift using Swift Package Manager (no Xcode project files). Supports Apple Silicon (arm64) only.

## Build Commands

```bash
make build          # Build debug version (fetches epithet binary if needed)
make build-release  # Build release version
make bundle         # Create .app bundle (debug)
make bundle-release # Create .app bundle (release)
make run            # Build and run executable directly
make run-bundle     # Build bundle and open app
make clean          # Remove build artifacts
make install        # Install release bundle to /Applications
make fetch-epithet  # Manually fetch epithet binary from GitHub releases
```

## Architecture

This is a menubar-only app (no dock icon, no main window). The `LSUIElement` key in Info.plist hides the app from the dock.

### Source Files

- `main.swift` - App entry point, sets up NSApplication with `.accessory` activation policy
- `AppDelegate.swift` - Application lifecycle, main menu setup (Edit/Window menus), owns StatusBarController
- `StatusBarController.swift` - NSStatusItem management, menubar menu with broker status indicators, Launch at Login toggle
- `BrokerConfig.swift` - Data model for broker configuration (AuthMethod, Verbosity enums)
- `BrokerConfigStore.swift` - JSON persistence in ~/Library/Application Support/EpithetAgent/
- `BrokerManager.swift` - Broker process lifecycle, stdout/stderr capture, runtime state management
- `SSHConfigManager.swift` - Manages ~/.ssh/config Include directive and generates ssh-config.conf
- `ConfigurationWindowController.swift` - Split-view broker configuration UI (NSSplitView + NSStackView)
- `InspectWindowController.swift` - Tabbed inspection UI showing broker status and live logs
- `PreferencesWindowController.swift` - App preferences (if present)

### Key Patterns

- Uses AppKit directly (not SwiftUI) for all UI
- NSTextFieldDelegate for auto-save on text field changes
- Process with Pipe for capturing broker stdout/stderr
- SMAppService for Launch at Login functionality
- Brokers run in ~/.epithet/<broker-hash>/ directories (managed by epithet binary)

## Project Structure

```
Sources/EpithetAgent/   # Swift source files
Resources/              # Info.plist, AppIcon.icns, epithet binary (fetched)
Package.swift           # SPM package definition
Makefile                # Build automation
SPEC.md                 # Feature specification
```

## Configuration Storage

- Broker configs: `~/Library/Application Support/EpithetAgent/config.json`
- SSH config fragment: `~/Library/Application Support/EpithetAgent/ssh-config.conf`
- SSH integration: Adds Include directive to `~/.ssh/config`
