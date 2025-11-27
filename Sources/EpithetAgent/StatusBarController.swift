import AppKit

class StatusBarController {
    private var statusItem: NSStatusItem
    private var menu: NSMenu

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        menu = NSMenu()

        setupStatusBarButton()
        setupMenu()
    }

    private func setupStatusBarButton() {
        if let button = statusItem.button {
            // Using SF Symbol for the menubar icon
            if let image = NSImage(systemSymbolName: "key.fill", accessibilityDescription: "Epithet Agent") {
                image.isTemplate = true  // Adapts to light/dark mode
                button.image = image
            } else {
                // Fallback to text if symbol not available
                button.title = "E"
            }
        }
    }

    private func setupMenu() {
        // Status section
        let statusItem = NSMenuItem(title: "Status: Not Running", action: nil, keyEquivalent: "")
        statusItem.isEnabled = false
        menu.addItem(statusItem)

        menu.addItem(NSMenuItem.separator())

        // Agent controls
        menu.addItem(NSMenuItem(title: "Start Agent", action: #selector(startAgent), keyEquivalent: "s"))
        menu.addItem(NSMenuItem(title: "Stop Agent", action: #selector(stopAgent), keyEquivalent: ""))

        menu.addItem(NSMenuItem.separator())

        // Preferences
        menu.addItem(NSMenuItem(title: "Preferences...", action: #selector(openPreferences), keyEquivalent: ","))

        menu.addItem(NSMenuItem.separator())

        // Quit
        menu.addItem(NSMenuItem(title: "Quit Epithet", action: #selector(quitApp), keyEquivalent: "q"))

        // Set targets for menu items
        for item in menu.items {
            item.target = self
        }

        self.statusItem.menu = menu
    }

    @objc private func startAgent() {
        // TODO: Implement agent start logic
        print("Starting agent...")
        updateStatus("Running")
    }

    @objc private func stopAgent() {
        // TODO: Implement agent stop logic
        print("Stopping agent...")
        updateStatus("Not Running")
    }

    @objc private func openPreferences() {
        // TODO: Implement preferences window
        print("Opening preferences...")
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    private func updateStatus(_ status: String) {
        if let statusMenuItem = menu.items.first {
            statusMenuItem.title = "Status: \(status)"
        }
    }
}
