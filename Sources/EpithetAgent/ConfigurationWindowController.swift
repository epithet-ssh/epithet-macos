import AppKit

class ConfigurationWindowController: NSWindowController {
    private let configStore = BrokerConfigStore.shared
    private let brokerManager = BrokerManager.shared

    private var splitView: NSSplitView!
    private var brokerListView: NSTableView!
    private var detailContainer: NSView!

    // Detail form fields
    private var nameField: NSTextField!
    private var caURLsTableView: NSTableView!
    private var caURLsScrollView: NSScrollView!
    private var addURLButton: NSButton!
    private var removeURLButton: NSButton!
    private var currentCAURLs: [String] = []
    private var authMethodPopup: NSPopUpButton!
    private var oidcIssuerField: NSTextField!
    private var oidcClientIDField: NSTextField!
    private var oidcClientSecretField: NSSecureTextField!
    private var authCommandField: NSTextField!
    private var caTimeoutField: NSTextField!
    private var caCooldownField: NSTextField!
    private var verbosityPopup: NSPopUpButton!
    private var startOnLoginCheckbox: NSButton!

    // Containers for conditional fields
    private var oidcFieldsView: NSStackView!
    private var commandFieldsView: NSStackView!

    private var selectedBrokerIndex: Int? {
        didSet {
            updateDetailView()
        }
    }

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 500),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Configure Brokers"
        window.center()
        window.minSize = NSSize(width: 700, height: 400)

        self.init(window: window)
        setupUI()
    }

    private func setupUI() {
        guard let window = window, let contentView = window.contentView else { return }

        // Create split view
        splitView = NSSplitView()
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(splitView)

        NSLayoutConstraint.activate([
            splitView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            splitView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            splitView.topAnchor.constraint(equalTo: contentView.topAnchor),
            splitView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])

        // Left panel - broker list
        let leftPanel = createBrokerListPanel()
        splitView.addSubview(leftPanel)

        // Right panel - detail view
        let rightPanel = createDetailPanel()
        splitView.addSubview(rightPanel)

        // Set initial split position
        splitView.setPosition(200, ofDividerAt: 0)

        // Load data
        brokerListView.reloadData()
        if !configStore.brokers.isEmpty {
            brokerListView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
            selectedBrokerIndex = 0
        }
    }

    private func createBrokerListPanel() -> NSView {
        let panel = NSView()
        panel.translatesAutoresizingMaskIntoConstraints = false

        // Scroll view for table
        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder

        // Table view
        brokerListView = NSTableView()
        brokerListView.delegate = self
        brokerListView.dataSource = self
        brokerListView.headerView = nil
        brokerListView.rowHeight = 32

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("broker"))
        column.width = 180
        brokerListView.addTableColumn(column)

        scrollView.documentView = brokerListView
        panel.addSubview(scrollView)

        // Button bar at bottom
        let addButton = NSButton(title: "+", target: self, action: #selector(addBroker))
        addButton.translatesAutoresizingMaskIntoConstraints = false
        addButton.bezelStyle = .smallSquare
        panel.addSubview(addButton)

        let removeButton = NSButton(title: "−", target: self, action: #selector(removeBroker))
        removeButton.translatesAutoresizingMaskIntoConstraints = false
        removeButton.bezelStyle = .smallSquare
        panel.addSubview(removeButton)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: panel.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: panel.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: addButton.topAnchor, constant: -8),

            addButton.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 8),
            addButton.bottomAnchor.constraint(equalTo: panel.bottomAnchor, constant: -8),
            addButton.widthAnchor.constraint(equalToConstant: 30),

            removeButton.leadingAnchor.constraint(equalTo: addButton.trailingAnchor, constant: 4),
            removeButton.bottomAnchor.constraint(equalTo: panel.bottomAnchor, constant: -8),
            removeButton.widthAnchor.constraint(equalToConstant: 30)
        ])

        // Set minimum width for left panel
        panel.widthAnchor.constraint(greaterThanOrEqualToConstant: 150).isActive = true

        return panel
    }

    private func createDetailPanel() -> NSView {
        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        detailContainer = NSView()
        detailContainer.translatesAutoresizingMaskIntoConstraints = false

        // Create main stack view for form
        let mainStack = NSStackView()
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        mainStack.orientation = .vertical
        mainStack.alignment = .leading
        mainStack.spacing = 16
        mainStack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)

        // Name field
        let nameRow = createLabeledField(label: "Name:", field: &nameField)
        mainStack.addArrangedSubview(nameRow)

        // CA URLs list
        let caURLsRow = createCAURLsRow()
        mainStack.addArrangedSubview(caURLsRow)

        // Auth method
        let authMethodRow = createAuthMethodRow()
        mainStack.addArrangedSubview(authMethodRow)

        // OIDC fields (conditional)
        oidcFieldsView = createOIDCFieldsView()
        mainStack.addArrangedSubview(oidcFieldsView)

        // Command field (conditional)
        commandFieldsView = createCommandFieldsView()
        mainStack.addArrangedSubview(commandFieldsView)

        // Separator
        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        mainStack.addArrangedSubview(separator)
        separator.widthAnchor.constraint(equalToConstant: 400).isActive = true

        // Advanced section
        let advancedLabel = NSTextField(labelWithString: "Advanced")
        advancedLabel.font = NSFont.boldSystemFont(ofSize: 12)
        mainStack.addArrangedSubview(advancedLabel)

        // Timeout row
        let timeoutRow = createTimeoutRow()
        mainStack.addArrangedSubview(timeoutRow)

        // Cooldown row
        let cooldownRow = createCooldownRow()
        mainStack.addArrangedSubview(cooldownRow)

        // Verbosity row
        let verbosityRow = createVerbosityRow()
        mainStack.addArrangedSubview(verbosityRow)

        // Start with app
        startOnLoginCheckbox = NSButton(checkboxWithTitle: "Start when app launches", target: self, action: #selector(fieldChanged))
        mainStack.addArrangedSubview(startOnLoginCheckbox)

        detailContainer.addSubview(mainStack)

        NSLayoutConstraint.activate([
            mainStack.leadingAnchor.constraint(equalTo: detailContainer.leadingAnchor),
            mainStack.trailingAnchor.constraint(equalTo: detailContainer.trailingAnchor),
            mainStack.topAnchor.constraint(equalTo: detailContainer.topAnchor),
            mainStack.bottomAnchor.constraint(lessThanOrEqualTo: detailContainer.bottomAnchor)
        ])

        scrollView.documentView = detailContainer

        // Make document view fill scroll view
        NSLayoutConstraint.activate([
            detailContainer.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            detailContainer.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
            detailContainer.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            detailContainer.heightAnchor.constraint(greaterThanOrEqualTo: scrollView.contentView.heightAnchor)
        ])

        return scrollView
    }

    private func createLabeledField(label: String, field: inout NSTextField!, placeholder: String? = nil, width: CGFloat = 200) -> NSStackView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 8
        row.alignment = .firstBaseline

        let labelView = NSTextField(labelWithString: label)
        labelView.widthAnchor.constraint(equalToConstant: 100).isActive = true
        labelView.alignment = .right

        field = NSTextField()
        field.translatesAutoresizingMaskIntoConstraints = false
        field.widthAnchor.constraint(equalToConstant: width).isActive = true
        if let placeholder = placeholder {
            field.placeholderString = placeholder
        }
        field.delegate = self

        row.addArrangedSubview(labelView)
        row.addArrangedSubview(field)

        return row
    }

    private func createCAURLsRow() -> NSStackView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 8
        row.alignment = .top

        let label = NSTextField(labelWithString: "CA URLs:")
        label.widthAnchor.constraint(equalToConstant: 100).isActive = true
        label.alignment = .right

        // Container for table and buttons
        let container = NSStackView()
        container.orientation = .vertical
        container.spacing = 4
        container.alignment = .leading

        // Scroll view for table
        caURLsScrollView = NSScrollView()
        caURLsScrollView.translatesAutoresizingMaskIntoConstraints = false
        caURLsScrollView.hasVerticalScroller = true
        caURLsScrollView.borderType = .bezelBorder

        // Table view
        caURLsTableView = NSTableView()
        caURLsTableView.delegate = self
        caURLsTableView.dataSource = self
        caURLsTableView.headerView = nil
        caURLsTableView.rowHeight = 22
        caURLsTableView.usesAlternatingRowBackgroundColors = true

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("url"))
        column.width = 430
        column.isEditable = true
        caURLsTableView.addTableColumn(column)

        caURLsScrollView.documentView = caURLsTableView

        NSLayoutConstraint.activate([
            caURLsScrollView.widthAnchor.constraint(equalToConstant: 450),
            caURLsScrollView.heightAnchor.constraint(equalToConstant: 80)
        ])

        container.addArrangedSubview(caURLsScrollView)

        // Button row
        let buttonRow = NSStackView()
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 4

        addURLButton = NSButton(title: "+", target: self, action: #selector(addCAURL))
        addURLButton.bezelStyle = .smallSquare
        addURLButton.widthAnchor.constraint(equalToConstant: 24).isActive = true

        removeURLButton = NSButton(title: "−", target: self, action: #selector(removeCAURL))
        removeURLButton.bezelStyle = .smallSquare
        removeURLButton.widthAnchor.constraint(equalToConstant: 24).isActive = true

        buttonRow.addArrangedSubview(addURLButton)
        buttonRow.addArrangedSubview(removeURLButton)

        container.addArrangedSubview(buttonRow)

        row.addArrangedSubview(label)
        row.addArrangedSubview(container)

        return row
    }

    @objc private func addCAURL() {
        currentCAURLs.append("https://")
        caURLsTableView.reloadData()
        let newRow = currentCAURLs.count - 1
        caURLsTableView.selectRowIndexes(IndexSet(integer: newRow), byExtendingSelection: false)
        caURLsTableView.editColumn(0, row: newRow, with: nil, select: true)
        fieldChanged()
    }

    @objc private func removeCAURL() {
        let selectedRow = caURLsTableView.selectedRow
        guard selectedRow >= 0 && selectedRow < currentCAURLs.count else { return }
        currentCAURLs.remove(at: selectedRow)
        caURLsTableView.reloadData()
        fieldChanged()
    }

    private func createAuthMethodRow() -> NSStackView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 8
        row.alignment = .firstBaseline

        let label = NSTextField(labelWithString: "Authentication:")
        label.widthAnchor.constraint(equalToConstant: 100).isActive = true
        label.alignment = .right

        authMethodPopup = NSPopUpButton()
        authMethodPopup.translatesAutoresizingMaskIntoConstraints = false
        for method in AuthMethod.allCases {
            authMethodPopup.addItem(withTitle: method.displayName)
        }
        authMethodPopup.target = self
        authMethodPopup.action = #selector(authMethodChanged)

        row.addArrangedSubview(label)
        row.addArrangedSubview(authMethodPopup)

        return row
    }

    private func createOIDCFieldsView() -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12

        // Issuer
        var issuerField: NSTextField!
        let issuerRow = createLabeledField(label: "Issuer:", field: &issuerField, placeholder: "https://accounts.google.com", width: 450)
        oidcIssuerField = issuerField
        stack.addArrangedSubview(issuerRow)

        // Client ID
        var clientIDField: NSTextField!
        let clientIDRow = createLabeledField(label: "Client ID:", field: &clientIDField, width: 450)
        oidcClientIDField = clientIDField
        stack.addArrangedSubview(clientIDRow)

        // Client Secret
        let secretRow = NSStackView()
        secretRow.orientation = .horizontal
        secretRow.spacing = 8
        secretRow.alignment = .firstBaseline

        let secretLabel = NSTextField(labelWithString: "Client Secret:")
        secretLabel.widthAnchor.constraint(equalToConstant: 100).isActive = true
        secretLabel.alignment = .right

        oidcClientSecretField = NSSecureTextField()
        oidcClientSecretField.translatesAutoresizingMaskIntoConstraints = false
        oidcClientSecretField.widthAnchor.constraint(equalToConstant: 450).isActive = true
        oidcClientSecretField.placeholderString = "(optional)"
        oidcClientSecretField.delegate = self

        secretRow.addArrangedSubview(secretLabel)
        secretRow.addArrangedSubview(oidcClientSecretField)
        stack.addArrangedSubview(secretRow)

        return stack
    }

    private func createCommandFieldsView() -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12

        var cmdField: NSTextField!
        let cmdRow = createLabeledField(label: "Command:", field: &cmdField, width: 450)
        authCommandField = cmdField
        stack.addArrangedSubview(cmdRow)

        return stack
    }

    private func createTimeoutRow() -> NSStackView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 8
        row.alignment = .firstBaseline

        let label = NSTextField(labelWithString: "CA Timeout:")
        label.widthAnchor.constraint(equalToConstant: 100).isActive = true
        label.alignment = .right

        caTimeoutField = NSTextField()
        caTimeoutField.translatesAutoresizingMaskIntoConstraints = false
        caTimeoutField.widthAnchor.constraint(equalToConstant: 60).isActive = true
        caTimeoutField.delegate = self

        let suffix = NSTextField(labelWithString: "seconds")

        row.addArrangedSubview(label)
        row.addArrangedSubview(caTimeoutField)
        row.addArrangedSubview(suffix)

        return row
    }

    private func createCooldownRow() -> NSStackView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 8
        row.alignment = .firstBaseline

        let label = NSTextField(labelWithString: "Cooldown:")
        label.widthAnchor.constraint(equalToConstant: 100).isActive = true
        label.alignment = .right

        caCooldownField = NSTextField()
        caCooldownField.translatesAutoresizingMaskIntoConstraints = false
        caCooldownField.widthAnchor.constraint(equalToConstant: 60).isActive = true
        caCooldownField.delegate = self

        let suffix = NSTextField(labelWithString: "seconds")

        row.addArrangedSubview(label)
        row.addArrangedSubview(caCooldownField)
        row.addArrangedSubview(suffix)

        return row
    }

    private func createVerbosityRow() -> NSStackView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 8
        row.alignment = .firstBaseline

        let label = NSTextField(labelWithString: "Log Level:")
        label.widthAnchor.constraint(equalToConstant: 100).isActive = true
        label.alignment = .right

        verbosityPopup = NSPopUpButton()
        verbosityPopup.translatesAutoresizingMaskIntoConstraints = false
        for level in Verbosity.allCases {
            verbosityPopup.addItem(withTitle: level.displayName)
        }
        verbosityPopup.target = self
        verbosityPopup.action = #selector(fieldChanged)

        row.addArrangedSubview(label)
        row.addArrangedSubview(verbosityPopup)

        return row
    }

    private func updateDetailView() {
        guard let index = selectedBrokerIndex, index < configStore.brokers.count else {
            setFieldsEnabled(false)
            clearFields()
            return
        }

        setFieldsEnabled(true)
        let broker = configStore.brokers[index]

        nameField.stringValue = broker.name
        currentCAURLs = broker.caURLs
        caURLsTableView.reloadData()
        authMethodPopup.selectItem(at: AuthMethod.allCases.firstIndex(of: broker.authMethod) ?? 0)
        oidcIssuerField.stringValue = broker.oidcIssuer ?? ""
        oidcClientIDField.stringValue = broker.oidcClientID ?? ""
        oidcClientSecretField.stringValue = broker.oidcClientSecret ?? ""
        authCommandField.stringValue = broker.authCommand ?? ""
        caTimeoutField.stringValue = String(broker.caTimeout)
        caCooldownField.stringValue = String(broker.caCooldown)
        verbosityPopup.selectItem(at: Verbosity.allCases.firstIndex(of: broker.verbosity) ?? 1)
        startOnLoginCheckbox.state = broker.startOnLogin ? .on : .off

        updateAuthFieldsVisibility()
    }

    private func setFieldsEnabled(_ enabled: Bool) {
        nameField?.isEnabled = enabled
        caURLsTableView?.isEnabled = enabled
        addURLButton?.isEnabled = enabled
        removeURLButton?.isEnabled = enabled
        authMethodPopup?.isEnabled = enabled
        oidcIssuerField?.isEnabled = enabled
        oidcClientIDField?.isEnabled = enabled
        oidcClientSecretField?.isEnabled = enabled
        authCommandField?.isEnabled = enabled
        caTimeoutField?.isEnabled = enabled
        caCooldownField?.isEnabled = enabled
        verbosityPopup?.isEnabled = enabled
        startOnLoginCheckbox?.isEnabled = enabled
    }

    private func clearFields() {
        nameField?.stringValue = ""
        currentCAURLs = []
        caURLsTableView?.reloadData()
        authMethodPopup?.selectItem(at: 0)
        oidcIssuerField?.stringValue = ""
        oidcClientIDField?.stringValue = ""
        oidcClientSecretField?.stringValue = ""
        authCommandField?.stringValue = ""
        caTimeoutField?.stringValue = ""
        caCooldownField?.stringValue = ""
        verbosityPopup?.selectItem(at: 1)  // Default to Info
        startOnLoginCheckbox?.state = .off
    }

    private func updateAuthFieldsVisibility() {
        let method = AuthMethod.allCases[authMethodPopup.indexOfSelectedItem]
        oidcFieldsView.isHidden = method != .oidc
        commandFieldsView.isHidden = method != .command
    }

    @objc private func addBroker() {
        let name = configStore.generateUniqueName()
        let broker = BrokerConfig(name: name)
        configStore.add(broker)
        brokerListView.reloadData()

        let newIndex = configStore.brokers.count - 1
        brokerListView.selectRowIndexes(IndexSet(integer: newIndex), byExtendingSelection: false)
        selectedBrokerIndex = newIndex

        // Focus the name field for editing
        window?.makeFirstResponder(nameField)
        nameField.selectText(nil)
    }

    @objc private func removeBroker() {
        guard let index = selectedBrokerIndex else { return }

        let broker = configStore.brokers[index]

        // Stop if running
        if brokerManager.state(for: broker.name).isRunning {
            brokerManager.stop(brokerName: broker.name)
        }

        configStore.remove(at: index)
        brokerListView.reloadData()

        if configStore.brokers.isEmpty {
            selectedBrokerIndex = nil
        } else {
            let newIndex = min(index, configStore.brokers.count - 1)
            brokerListView.selectRowIndexes(IndexSet(integer: newIndex), byExtendingSelection: false)
            selectedBrokerIndex = newIndex
        }
    }

    @objc private func authMethodChanged() {
        updateAuthFieldsVisibility()
        fieldChanged()
    }

    @objc private func fieldChanged() {
        guard let index = selectedBrokerIndex, index < configStore.brokers.count else { return }

        var broker = configStore.brokers[index]
        let oldName = broker.name

        broker.name = nameField.stringValue
        broker.caURLs = currentCAURLs
        broker.authMethod = AuthMethod.allCases[authMethodPopup.indexOfSelectedItem]
        broker.oidcIssuer = oidcIssuerField.stringValue.isEmpty ? nil : oidcIssuerField.stringValue
        broker.oidcClientID = oidcClientIDField.stringValue.isEmpty ? nil : oidcClientIDField.stringValue
        broker.oidcClientSecret = oidcClientSecretField.stringValue.isEmpty ? nil : oidcClientSecretField.stringValue
        broker.authCommand = authCommandField.stringValue.isEmpty ? nil : authCommandField.stringValue
        broker.caTimeout = Int(caTimeoutField.stringValue) ?? 15
        broker.caCooldown = Int(caCooldownField.stringValue) ?? 600
        broker.verbosity = Verbosity.allCases[verbosityPopup.indexOfSelectedItem]
        broker.startOnLogin = startOnLoginCheckbox.state == .on

        // If name changed, we need special handling
        if oldName != broker.name {
            configStore.remove(at: index)
            configStore.add(broker)
            brokerListView.reloadData()
            if let newIndex = configStore.brokers.firstIndex(where: { $0.name == broker.name }) {
                brokerListView.selectRowIndexes(IndexSet(integer: newIndex), byExtendingSelection: false)
                selectedBrokerIndex = newIndex
            }
        } else {
            configStore.update(broker)
            brokerListView.reloadData()
        }
    }

    func showWindow() {
        brokerListView?.reloadData()
        updateDetailView()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

extension ConfigurationWindowController: NSTextFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        guard let textField = obj.object as? NSTextField else {
            fieldChanged()
            return
        }

        // Check if this is a URL table cell edit
        if textField.superview is NSTableCellView,
           let row = caURLsTableView?.row(for: textField),
           row >= 0 && row < currentCAURLs.count {
            currentCAURLs[row] = textField.stringValue
        }

        // Auto-save on every keystroke
        fieldChanged()
    }
}

extension ConfigurationWindowController: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        if tableView === caURLsTableView {
            return currentCAURLs.count
        }
        return configStore.brokers.count
    }

    func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
        if tableView === caURLsTableView {
            return currentCAURLs[row]
        }
        return nil
    }

    func tableView(_ tableView: NSTableView, setObjectValue object: Any?, for tableColumn: NSTableColumn?, row: Int) {
        if tableView === caURLsTableView, let value = object as? String {
            currentCAURLs[row] = value
            fieldChanged()
        }
    }
}

extension ConfigurationWindowController: NSTableViewDelegate {
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        if tableView === caURLsTableView {
            let cell = NSTableCellView()
            cell.identifier = NSUserInterfaceItemIdentifier("URLCell")

            let textField = NSTextField()
            textField.stringValue = currentCAURLs[row]
            textField.isBordered = false
            textField.drawsBackground = false
            textField.isEditable = true
            textField.delegate = self
            textField.frame = NSRect(x: 2, y: 0, width: 426, height: 20)
            textField.tag = row
            cell.addSubview(textField)
            cell.textField = textField

            return cell
        }

        // Broker list table
        let broker = configStore.brokers[row]
        let state = brokerManager.state(for: broker.name)

        let cell = NSTableCellView()
        cell.identifier = NSUserInterfaceItemIdentifier("BrokerCell")

        // Status indicator
        let indicator = NSView(frame: NSRect(x: 8, y: 11, width: 10, height: 10))
        indicator.wantsLayer = true
        indicator.layer?.cornerRadius = 5

        switch state {
        case .running:
            indicator.layer?.backgroundColor = NSColor.systemGreen.cgColor
        case .starting:
            indicator.layer?.backgroundColor = NSColor.systemYellow.cgColor
        case .error:
            indicator.layer?.backgroundColor = NSColor.systemRed.cgColor
        case .stopped:
            indicator.layer?.backgroundColor = NSColor.systemGray.cgColor
        }

        cell.addSubview(indicator)

        // Broker name
        let textField = NSTextField(labelWithString: broker.name)
        textField.frame = NSRect(x: 24, y: 6, width: 150, height: 20)
        textField.lineBreakMode = .byTruncatingTail
        cell.addSubview(textField)
        cell.textField = textField

        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard let tableView = notification.object as? NSTableView else { return }
        if tableView === brokerListView {
            let row = brokerListView.selectedRow
            selectedBrokerIndex = row >= 0 ? row : nil
        }
    }
}
