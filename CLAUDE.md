# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Epithet for Mac - A macOS menubar application to manage epithet agents. Built with Swift using Swift Package Manager (no Xcode project files).

## Build Commands

```bash
make build          # Build debug version
make build-release  # Build release version
make bundle         # Create .app bundle (debug)
make bundle-release # Create .app bundle (release)
make run            # Build and run executable directly
make run-bundle     # Build bundle and open app
make clean          # Remove build artifacts
make install        # Install release bundle to /Applications
```

## Architecture

This is a menubar-only app (no dock icon, no main window). Key components:

- `main.swift` - App entry point, sets up NSApplication with `.accessory` activation policy
- `AppDelegate.swift` - Application lifecycle, owns the StatusBarController
- `StatusBarController.swift` - Manages NSStatusItem and menu, handles user interactions

The app uses AppKit directly (not SwiftUI) for menubar management. The `LSUIElement` key in Info.plist hides the app from the dock.

## Project Structure

```
Sources/EpithetAgent/   # Swift source files
Resources/              # Info.plist and other resources
Package.swift           # SPM package definition
Makefile               # Build automation
```
