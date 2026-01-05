import AppKit
import ServiceManagement

class StatusBarController {
    private var statusItem: NSStatusItem
    private var menu: NSMenu
    private let configStore = BrokerConfigStore.shared
    private let brokerManager = BrokerManager.shared

    private lazy var configurationWindowController = ConfigurationWindowController()
    private lazy var inspectWindowController = InspectWindowController()

    private var brokerMenuItems: [NSMenuItem] = []
    private var launchAtLoginItem: NSMenuItem!

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        menu = NSMenu()

        setupStatusBarButton()
        setupMenu()

        // Listen for broker state changes
        brokerManager.onStateChange = { [weak self] _, _ in
            self?.rebuildMenu()
        }

        // Listen for config changes
        configStore.onChange = { [weak self] in
            self?.rebuildMenu()
        }
    }

    private func setupStatusBarButton() {
        if let button = statusItem.button {
            if let image = NSImage(systemSymbolName: "key.fill", accessibilityDescription: "Epithet Agent") {
                image.isTemplate = true
                button.image = image
            } else {
                button.title = "E"
            }
        }
    }

    private func setupMenu() {
        rebuildMenu()
        statusItem.menu = menu
    }

    private func rebuildMenu() {
        menu.removeAllItems()

        // Broker items
        if configStore.brokers.isEmpty {
            let noConfigItem = NSMenuItem(title: "No brokers configured", action: nil, keyEquivalent: "")
            noConfigItem.isEnabled = false
            menu.addItem(noConfigItem)
        } else {
            for broker in configStore.brokers {
                let item = createBrokerMenuItem(for: broker)
                menu.addItem(item)
            }
        }

        menu.addItem(NSMenuItem.separator())

        // Inspect
        let inspectItem = NSMenuItem(title: "Inspect...", action: #selector(openInspect), keyEquivalent: "i")
        inspectItem.target = self
        menu.addItem(inspectItem)

        // Configure
        let configureItem = NSMenuItem(title: "Configure Brokers...", action: #selector(openConfiguration), keyEquivalent: ",")
        configureItem.target = self
        menu.addItem(configureItem)

        menu.addItem(NSMenuItem.separator())

        // Launch at Login
        launchAtLoginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchAtLoginItem.target = self
        launchAtLoginItem.state = isLaunchAtLoginEnabled() ? .on : .off
        menu.addItem(launchAtLoginItem)

        menu.addItem(NSMenuItem.separator())

        // Quit
        let quitItem = NSMenuItem(title: "Quit Epithet", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    private func isLaunchAtLoginEnabled() -> Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return false
    }

    @objc private func toggleLaunchAtLogin() {
        if #available(macOS 13.0, *) {
            do {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                    launchAtLoginItem.state = .off
                } else {
                    try SMAppService.mainApp.register()
                    launchAtLoginItem.state = .on
                }
            } catch {
                print("Failed to toggle launch at login: \(error)")
            }
        }
    }

    private func createBrokerMenuItem(for broker: BrokerConfig) -> NSMenuItem {
        let state = brokerManager.state(for: broker.name)
        let item = NSMenuItem(title: broker.name, action: #selector(toggleBroker(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = broker.name

        // Set state indicator via image
        let indicatorImage: NSImage?
        switch state {
        case .running:
            indicatorImage = NSImage(systemSymbolName: "circle.fill", accessibilityDescription: "Running")
            indicatorImage?.isTemplate = false
            item.image = indicatorImage?.tinted(with: .systemGreen)
        case .starting:
            indicatorImage = NSImage(systemSymbolName: "circle.fill", accessibilityDescription: "Starting")
            indicatorImage?.isTemplate = false
            item.image = indicatorImage?.tinted(with: .systemYellow)
        case .error:
            indicatorImage = NSImage(systemSymbolName: "exclamationmark.circle.fill", accessibilityDescription: "Error")
            indicatorImage?.isTemplate = false
            item.image = indicatorImage?.tinted(with: .systemRed)
        case .stopped:
            indicatorImage = NSImage(systemSymbolName: "circle", accessibilityDescription: "Stopped")
            item.image = indicatorImage
        }

        return item
    }

    @objc private func toggleBroker(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        brokerManager.toggle(brokerName: name)
    }

    @objc private func openInspect() {
        inspectWindowController.showWindow()
    }

    @objc private func openConfiguration() {
        configurationWindowController.showWindow()
    }

    @objc private func quitApp() {
        brokerManager.stopAll()
        NSApplication.shared.terminate(nil)
    }
}

extension NSImage {
    func tinted(with color: NSColor) -> NSImage {
        let image = self.copy() as! NSImage
        image.lockFocus()
        color.set()
        let imageRect = NSRect(origin: .zero, size: image.size)
        imageRect.fill(using: .sourceAtop)
        image.unlockFocus()
        return image
    }
}
