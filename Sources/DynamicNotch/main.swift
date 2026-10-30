import AppKit
import NotchKit

// Claude Code calls the app as its permission hook; that run answers and quits.
AgentHookClient.runIfRequested()

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.run()
