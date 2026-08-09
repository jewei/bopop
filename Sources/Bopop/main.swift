import AppKit
import BopopKit

let app = NSApplication.shared
let appDelegate = PerformanceSignposts.lifecycle.interval("App Construction") {
    AppDelegate()
}

app.delegate = appDelegate
_ = app.setActivationPolicy(.accessory)
app.run()
