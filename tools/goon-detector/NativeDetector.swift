import AppKit

final class AlertWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) {
        (NSApp.delegate as? DetectorApp)?.dismiss()
    }
}

final class DetectorApp: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var statusLine: NSMenuItem!
    var window: AlertWindow?
    var sound: NSSound?
    var worker: Process?
    var lastEvent = 0
    var previousApp: NSRunningApplication?
    let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "🥀 0%"
        let menu = NSMenu()
        statusLine = NSMenuItem(title: "Connecting to Pico…", action: nil, keyEquivalent: "")
        menu.addItem(statusLine)
        let test = NSMenuItem(title: "Test popup + audio", action: #selector(showAlert), keyEquivalent: "")
        test.target = self
        menu.addItem(test)
        let stop = NSMenuItem(title: "Dismiss / stop audio", action: #selector(dismiss), keyEquivalent: "")
        stop.target = self
        menu.addItem(stop)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit detector", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        statusItem.menu = menu

        let process = Process()
        process.executableURL = URL(fileURLWithPath: CommandLine.arguments[1])
        process.arguments = [root.appendingPathComponent("server.py").path, "--native"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.terminationHandler = { _ in
            DispatchQueue.main.async {
                self.statusLine.title = "Reader stopped — quit and relaunch detector."
                self.statusItem.button?.title = "🥀 Offline"
            }
        }
        do {
            try process.run()
            worker = process
        } catch {
            statusLine.title = "Cannot start Python: \(error.localizedDescription)"
            return
        }
        DispatchQueue.global(qos: .utility).async {
            var pending = Data()
            while true {
                let data = pipe.fileHandleForReading.availableData
                if data.isEmpty { break }
                pending.append(data)
                while let newline = pending.firstIndex(of: 10) {
                    let line = pending.prefix(upTo: newline)
                    if let state = try? JSONSerialization.jsonObject(with: line) as? [String: Any] {
                        let score = state["suspicion"] as? Int ?? 0
                        let event = state["event"] as? Int ?? 0
                        let connected = state["connected"] as? Bool ?? false
                        let waiting = state["waiting"] as? Bool ?? false
                        let status = state["status"] as? String ?? "Disconnected"
                        DispatchQueue.main.async {
                            self.statusItem.button?.title = waiting ? "🥀 Waiting" : (connected ? "🥀 \(score)%" : "🥀 Offline")
                            self.statusLine.title = status
                            if event > self.lastEvent && connected { self.showAlert() }
                            self.lastEvent = event
                        }
                    }
                    pending.removeSubrange(...newline)
                }
            }
        }
    }

    @objc func showAlert() {
        guard window == nil else { return }
        previousApp = NSWorkspace.shared.frontmostApplication
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main else { return }
        let panel = AlertWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = NSColor(calibratedRed: 0.84, green: 1, blue: 0.44, alpha: 1)
        panel.isReleasedWhenClosed = false
        let label = NSTextField(wrappingLabelWithString: "gooning at work\nis crazy vro 🥀")
        label.font = NSFont.systemFont(ofSize: min(130, screen.frame.width / 12), weight: .black)
        label.textColor = .black
        label.alignment = .center
        let button = NSButton(title: "Dismiss / stop audio (Esc)", target: self, action: #selector(dismiss))
        button.bezelStyle = .rounded
        button.font = NSFont.systemFont(ofSize: 20, weight: .semibold)
        let stack = NSStackView(views: [label, button])
        stack.orientation = .vertical
        stack.spacing = 48
        stack.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView!.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: panel.contentView!.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: panel.contentView!.centerYAnchor),
            stack.widthAnchor.constraint(equalTo: panel.contentView!.widthAnchor, multiplier: 0.9),
            label.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
        window = panel
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        sound = NSSound(contentsOf: root.appendingPathComponent("jonkler-rap.mp3"), byReference: false)
        if sound?.play() != true { statusLine.title = "Audio unavailable — check jonkler-rap.mp3." }
    }

    @objc func dismiss() {
        sound?.stop()
        sound = nil
        window?.close()
        window = nil
        previousApp?.activate(options: [])
        previousApp = nil
    }

    @objc func quit() { NSApp.terminate(nil) }

    func applicationWillTerminate(_ notification: Notification) {
        sound?.stop()
        if worker?.isRunning == true { worker?.terminate() }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = DetectorApp()
app.delegate = delegate
app.run()
