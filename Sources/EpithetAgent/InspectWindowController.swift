import AppKit

class InspectWindowController: NSWindowController {
    private let brokerManager = BrokerManager.shared
    private let configStore = BrokerConfigStore.shared

    private var tabView: NSTabView!
    private var noRunningBrokersLabel: NSTextField!
    private var refreshButton: NSButton!
    private var autoRefreshTimer: Timer?

    private var logTextViews: [String: NSTextView] = [:]

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 550),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Inspect Brokers"
        window.center()
        window.minSize = NSSize(width: 550, height: 400)

        self.init(window: window)
        setupUI()
        setupLogUpdates()
    }

    private func setupUI() {
        guard let contentView = window?.contentView else { return }

        // Tab view for running brokers
        tabView = NSTabView()
        tabView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(tabView)

        // "No running brokers" label
        noRunningBrokersLabel = NSTextField(labelWithString: "No brokers are currently running.\nConfigure and start a broker to see status here.")
        noRunningBrokersLabel.translatesAutoresizingMaskIntoConstraints = false
        noRunningBrokersLabel.alignment = .center
        noRunningBrokersLabel.font = NSFont.systemFont(ofSize: 14)
        noRunningBrokersLabel.textColor = .secondaryLabelColor
        noRunningBrokersLabel.maximumNumberOfLines = 0
        contentView.addSubview(noRunningBrokersLabel)

        // Bottom bar with refresh button
        refreshButton = NSButton(title: "Refresh", target: self, action: #selector(refresh))
        refreshButton.translatesAutoresizingMaskIntoConstraints = false
        refreshButton.bezelStyle = .rounded
        contentView.addSubview(refreshButton)

        let autoRefreshCheckbox = NSButton(checkboxWithTitle: "Auto-refresh", target: self, action: #selector(toggleAutoRefresh))
        autoRefreshCheckbox.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(autoRefreshCheckbox)

        NSLayoutConstraint.activate([
            tabView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            tabView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            tabView.topAnchor.constraint(equalTo: contentView.topAnchor),
            tabView.bottomAnchor.constraint(equalTo: refreshButton.topAnchor, constant: -8),

            noRunningBrokersLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            noRunningBrokersLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),

            autoRefreshCheckbox.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            autoRefreshCheckbox.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),

            refreshButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            refreshButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12)
        ])
    }

    private func setupLogUpdates() {
        brokerManager.onLogUpdate = { [weak self] brokerName in
            self?.updateLogsForBroker(brokerName)
        }
    }

    private func updateLogsForBroker(_ brokerName: String) {
        guard let textView = logTextViews[brokerName] else { return }
        let logs = brokerManager.getLogs(for: brokerName)
        textView.string = logs

        // Scroll to bottom
        textView.scrollToEndOfDocument(nil)
    }

    func showWindow() {
        refresh()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func refresh() {
        // Remove existing tabs
        while tabView.numberOfTabViewItems > 0 {
            tabView.removeTabViewItem(tabView.tabViewItem(at: 0))
        }
        logTextViews.removeAll()

        // Show tabs for all configured brokers (not just running ones)
        let brokers = configStore.brokers

        if brokers.isEmpty {
            noRunningBrokersLabel.isHidden = false
            tabView.isHidden = true
            return
        }

        noRunningBrokersLabel.isHidden = true
        tabView.isHidden = false

        for broker in brokers {
            let tabItem = NSTabViewItem(identifier: broker.name)
            tabItem.label = broker.name

            let contentView = createBrokerView(for: broker.name)
            tabItem.view = contentView

            tabView.addTabViewItem(tabItem)
        }
    }

    private func createBrokerView(for brokerName: String) -> NSView {
        let state = brokerManager.state(for: brokerName)

        // Create split view with inspect on top, logs on bottom
        let splitView = NSSplitView(frame: NSRect(x: 0, y: 0, width: 680, height: 450))
        splitView.autoresizingMask = [.width, .height]
        splitView.isVertical = false  // horizontal split
        splitView.dividerStyle = .thin

        // Top: Inspect section
        let inspectSection = createInspectSection(for: brokerName, state: state)
        splitView.addSubview(inspectSection)

        // Bottom: Logs section
        let logsSection = createLogsSection(for: brokerName)
        splitView.addSubview(logsSection)

        // Set initial split position (55% inspect, 45% logs)
        DispatchQueue.main.async {
            splitView.setPosition(splitView.bounds.height * 0.55, ofDividerAt: 0)
        }

        return splitView
    }

    private func createInspectSection(for brokerName: String, state: BrokerState) -> NSView {
        let section = NSView(frame: NSRect(x: 0, y: 0, width: 680, height: 200))
        section.autoresizingMask = [.width, .height]

        // Section header
        let header = NSTextField(labelWithString: "Status")
        header.frame = NSRect(x: 8, y: section.bounds.height - 24, width: 200, height: 20)
        header.autoresizingMask = [.minYMargin]
        header.font = NSFont.boldSystemFont(ofSize: 12)
        section.addSubview(header)

        let scrollView = NSScrollView(frame: NSRect(x: 8, y: 4, width: section.bounds.width - 16, height: section.bounds.height - 32))
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder

        let textView = NSTextView(frame: scrollView.bounds)
        textView.isEditable = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        textView.autoresizingMask = [.width, .height]
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true

        if !state.isRunning {
            textView.string = "Broker is not running.\n\nClick the broker name in the menubar to start it."
            textView.textColor = .secondaryLabelColor
        } else {
            textView.string = "Loading..."
            // Fetch inspect data
            brokerManager.inspect(brokerName: brokerName) { [weak textView] output in
                DispatchQueue.main.async {
                    if let output = output {
                        textView?.textColor = .labelColor
                        textView?.string = output
                    } else {
                        textView?.textColor = .secondaryLabelColor
                        textView?.string = "Failed to get status"
                    }
                }
            }
        }

        scrollView.documentView = textView
        section.addSubview(scrollView)

        return section
    }

    private func createLogsSection(for brokerName: String) -> NSView {
        let section = NSView(frame: NSRect(x: 0, y: 0, width: 680, height: 200))
        section.autoresizingMask = [.width, .height]

        // Section header
        let header = NSTextField(labelWithString: "Logs")
        header.frame = NSRect(x: 8, y: section.bounds.height - 24, width: 200, height: 20)
        header.autoresizingMask = [.minYMargin]
        header.font = NSFont.boldSystemFont(ofSize: 12)
        section.addSubview(header)

        // Clear logs button
        let clearButton = NSButton(title: "Clear", target: self, action: #selector(clearLogs(_:)))
        clearButton.frame = NSRect(x: section.bounds.width - 60, y: section.bounds.height - 26, width: 50, height: 20)
        clearButton.autoresizingMask = [.minXMargin, .minYMargin]
        clearButton.bezelStyle = .inline
        clearButton.controlSize = .small
        clearButton.identifier = NSUserInterfaceItemIdentifier(brokerName)
        section.addSubview(clearButton)

        let scrollView = NSScrollView(frame: NSRect(x: 8, y: 4, width: section.bounds.width - 16, height: section.bounds.height - 32))
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder

        let textView = NSTextView(frame: scrollView.bounds)
        textView.isEditable = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        textView.autoresizingMask = [.width, .height]
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.backgroundColor = NSColor(white: 0.1, alpha: 1.0)
        textView.textColor = NSColor(white: 0.9, alpha: 1.0)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true

        // Load existing logs
        let logs = brokerManager.getLogs(for: brokerName)
        textView.string = logs.isEmpty ? "(no logs yet)" : logs

        scrollView.documentView = textView
        section.addSubview(scrollView)

        // Store reference for live updates
        logTextViews[brokerName] = textView

        return section
    }

    @objc private func clearLogs(_ sender: NSButton) {
        guard let brokerName = sender.identifier?.rawValue else { return }
        brokerManager.clearLogs(for: brokerName)
        if let textView = logTextViews[brokerName] {
            textView.string = "(logs cleared)"
        }
    }

    @objc private func toggleAutoRefresh(_ sender: NSButton) {
        if sender.state == .on {
            autoRefreshTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
                self?.refresh()
            }
        } else {
            autoRefreshTimer?.invalidate()
            autoRefreshTimer = nil
        }
    }

    deinit {
        autoRefreshTimer?.invalidate()
    }
}
