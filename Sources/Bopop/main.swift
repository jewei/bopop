import AppKit

let app = NSApplication.shared
let appDelegate = AppDelegate()

app.delegate = appDelegate
_ = app.setActivationPolicy(.accessory)
app.run()
