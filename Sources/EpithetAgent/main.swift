import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate

// Don't show in dock (menubar-only app)
app.setActivationPolicy(.accessory)

app.run()
