import AppKit
import IOKit.hid
import ServiceManagement
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, UNUserNotificationCenterDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let reader = ReaderProcess()
    private let notifications = UNUserNotificationCenter.current()
    private var timer: Timer?
    private var hidManager: IOHIDManager?
    private var wakeObserver: NSObjectProtocol?
    private var history = WarningHistory()
    private var percent: Int?
    private var measuredAt: Date?
    private var status = "Reading battery…"
    private var alertStatus = "Checking notification permission…"
    private var canNotify = false
    private var alertBusy = false
    private var lastWarningError: String?
    private var epoch = 0
    private var refreshAfterRead = false
    private var enabledWarnings: Bool {
        get { UserDefaults.standard.object(forKey: "warningsEnabled") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "warningsEnabled") }
    }
    private var sleepSetting: SleepSetting?
    private var sleepMessage = "Checking keyboard…"
    private var operation: KeyboardOperation = .idle
    private let stateURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/KeychronMenu/warnings.json")

    func applicationDidFinishLaunching(_ notification: Notification) {
        if NSWorkspace.shared.runningApplications.contains(where: {
            $0.bundleIdentifier == Bundle.main.bundleIdentifier && $0.processIdentifier != ProcessInfo.processInfo.processIdentifier
        }) {
            NSApp.terminate(nil)
            return
        }
        NSApp.setActivationPolicy(.accessory)
        if let data = try? Data(contentsOf: stateURL), let saved = try? JSONDecoder().decode(WarningHistory.self, from: data) {
            history = saved
        }
        if let url = Bundle.main.url(forResource: "Keychron", withExtension: "png"), let image = NSImage(contentsOf: url) {
            image.size = NSSize(width: 18, height: 18)
            image.isTemplate = true
            item.button?.image = image
            item.button?.imagePosition = .imageLeading
        }
        item.button?.setAccessibilityLabel("Keychron keyboard battery")
        item.menu = menu
        menu.delegate = self
        menu.autoenablesItems = false
        notifications.delegate = self
        updateNotificationPermission()
        if !UserDefaults.standard.bool(forKey: "hasRequestedNotifications") {
            UserDefaults.standard.set(true, forKey: "hasRequestedNotifications")
            notifications.requestAuthorization(options: [.alert, .sound]) { [weak self] _, _ in
                Task { @MainActor in self?.updateNotificationPermission() }
            }
        }
        render()
        refresh()
        timer = Timer(timeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshBattery(includeSleep: false) }
        }
        RunLoop.main.add(timer!, forMode: .common)
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in Task { @MainActor in self?.connectionChanged() } }
        observeConnections()
    }

    private func observeConnections() {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(manager, [kIOHIDProductKey: "Keychron K2", kIOHIDTransportKey: "Bluetooth"] as CFDictionary)
        let callback: IOHIDDeviceCallback = { context, _, _, _ in
            guard let context else { return }
            let owner = Unmanaged<AppDelegate>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor in owner.connectionChanged() }
        }
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, callback, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, callback, context)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        hidManager = manager
    }

    private func connectionChanged() {
        if operation.isChanging { refreshAfterRead = true; return }
        epoch += 1
        sleepSetting = nil
        sleepMessage = "Not connected"
        percent = nil
        status = "Checking Bluetooth connection…"
        if operation != .idle { refreshAfterRead = true } else { refresh() }
        render()
    }

    func menuWillOpen(_ menu: NSMenu) {
        updateNotificationPermission()
        refresh()
    }

    @objc private func refresh() { refreshBattery(includeSleep: true) }

    private func refreshBattery(includeSleep: Bool) {
        guard operation == .idle else { return }
        guard let executable = Bundle.main.url(forAuxiliaryExecutable: "BatteryReader") else {
            status = "Battery reader missing"; render(); return
        }
        operation = .refreshing
        render()
        let readEpoch = epoch
        reader.read(executable: executable) { [weak self] result in
            guard let self else { return }
            if readEpoch == self.epoch {
                switch result {
                case .success(let reply):
                    self.percent = reply.status == "fresh" ? reply.percent : nil
                    if let percent = self.percent {
                        self.measuredAt = Date()
                        self.status = "Connected over Bluetooth"
                        self.considerWarning(percent)
                    } else {
                        self.status = self.description(for: reply.status)
                    }
                case .failure(let error):
                    self.percent = nil
                    self.status = error is ReaderError ? "Invalid battery response" : error.localizedDescription
                }
                self.render()
            }
            if includeSleep { self.readSleep(epoch: readEpoch) }
            else { self.finishOperation() }
        }
    }

    private func readSleep(epoch readEpoch: Int) {
        guard let executable = Bundle.main.url(forAuxiliaryExecutable: "SleepControl") else {
            sleepSetting = nil; sleepMessage = "Sleep control unavailable"; finishOperation(); return
        }
        reader.run(executable: executable, arguments: ["read"], timeout: 12) { [weak self] result in
            guard let self else { return }
            if readEpoch == self.epoch { self.acceptSleep(result) }
            self.finishOperation()
        }
    }

    private func acceptSleep(_ result: Result<Data, Error>, expected: SleepSetting? = nil) {
        do {
            let reply = try SleepReply.parse(result.get())
            guard reply.status == "fresh", let setting = reply.sleep else {
                sleepSetting = nil
                switch reply.status {
                case "unsupported": sleepMessage = "Not supported on this firmware"
                case "disconnected": sleepMessage = "Not connected"
                case "accessDenied": sleepMessage = "Keyboard access required"
                case "busy": sleepMessage = "Keyboard is busy. Try Refresh."
                case "verificationFailed": sleepMessage = "Change not confirmed. Try Refresh."
                default: sleepMessage = "State unavailable. Try Refresh."
                }
                return
            }
            guard expected == nil || setting == expected else {
                sleepSetting = nil; sleepMessage = "Change not confirmed. Try Refresh."; return
            }
            sleepSetting = setting
            sleepMessage = "Changing this briefly reconnects the keyboard."
        } catch {
            sleepSetting = nil
            sleepMessage = expected == nil ? "State unavailable. Try Refresh." : "Change not confirmed. Try Refresh."
        }
    }

    private func finishOperation() {
        operation = .idle
        render()
        if refreshAfterRead {
            refreshAfterRead = false
            refresh()
        }
    }

    @objc private func toggleSleep(_ sender: NSSwitch) {
        guard operation == .idle, let current = sleepSetting,
              let executable = Bundle.main.url(forAuxiliaryExecutable: "SleepControl") else { render(); return }
        let desired = current.opposite
        operation = .changing(desired)
        sleepSetting = nil
        sleepMessage = "Reconnecting keyboard…"
        render()
        reader.run(executable: executable, arguments: [desired.rawValue], timeout: 45) { [weak self] result in
            guard let self else { return }
            self.acceptSleep(result, expected: desired)
            self.finishOperation()
        }
    }

    private func description(for status: String) -> String {
        switch status {
        case "disconnected": "Not connected over Bluetooth"
        case "accessDenied": "macOS denied keyboard access"
        case "unsupported": "Keyboard battery report unavailable"
        case "ambiguous": "Multiple K2 keyboards found"
        case "invalidReport": "Keyboard returned an invalid battery report"
        default: "Keyboard did not answer. Try Refresh."
        }
    }

    private func save(_ value: WarningHistory) throws {
        try FileManager.default.createDirectory(at: stateURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(value).write(to: stateURL, options: .atomic)
    }

    private func considerWarning(_ percent: Int) {
        guard !alertBusy else { return }
        var next = history
        next.rearm(percent: percent)
        if next != history {
            do { try save(next); history = next }
            catch { lastWarningError = "Could not save alert history"; return }
        }
        guard canNotify, enabledWarnings, let warning = history.pending(percent: percent) else { return }
        let previous = history
        next = history
        next.spend(warning)
        do { try save(next); history = next }
        catch { lastWarningError = "Could not save alert history"; return }
        alertBusy = true
        let content = UNMutableNotificationContent()
        content.title = warning == .critical ? "Keychron battery is very low" : "Time to charge your Keychron"
        content.body = "Your K2 reports \(percent)% battery. Plug it in to charge."
        content.sound = .default
        let request = UNNotificationRequest(identifier: "keychron-battery-\(warning.rawValue)", content: content, trigger: nil)
        notifications.add(request) { [weak self] error in
            Task { @MainActor in
                guard let self else { return }
                self.alertBusy = false
                if error != nil {
                    do { try self.save(previous); self.history = previous }
                    catch { self.lastWarningError = "Could not restore alert history" }
                    self.lastWarningError = "macOS could not submit the battery alert"
                } else { self.lastWarningError = nil }
                self.render()
            }
        }
    }

    private func updateNotificationPermission() {
        notifications.getNotificationSettings { [weak self] settings in
            let allowed = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
            let denied = settings.authorizationStatus == .denied
            Task { @MainActor in
                guard let self else { return }
                let wasAllowed = self.canNotify
                self.canNotify = allowed
                self.alertStatus = !self.enabledWarnings ? "Battery warnings paused" : allowed
                    ? "Warnings at 20% and 10%" : denied ? "Notifications blocked in System Settings" : "Enable notifications for battery warnings"
                self.render()
                if allowed && !wasAllowed { self.refresh() }
            }
        }
    }

    @objc private func toggleWarnings() {
        if canNotify {
            enabledWarnings.toggle()
            updateNotificationPermission()
            if enabledWarnings { refresh() }
        } else {
            enabledWarnings = true
            notifications.requestAuthorization(options: [.alert, .sound]) { [weak self] _, _ in
                Task { @MainActor in self?.updateNotificationPermission() }
            }
        }
    }

    @objc private func openNotificationSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!)
    }

    @objc private func openKeyboardSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!)
    }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
            lastWarningError = nil
        } catch { lastWarningError = "Login setting failed. \(error.localizedDescription)" }
        render()
    }

    private func render() {
        let sleepLabel: String
        if case .changing(let desired) = operation { sleepLabel = "Changing to \(desired.title)…" }
        else { sleepLabel = sleepSetting?.title ?? "Unavailable" }
        item.button?.title = percent.map { " \($0)%" } ?? " ?"
        item.button?.toolTip = "Keychron K2 · \(status) · Auto-sleep \(sleepLabel)"
        menu.removeAllItems()
        add("Keychron K2", enabled: false)
        add(percent.map { "Battery  \($0)%" } ?? "Battery  Unavailable", enabled: false)
        add(status, enabled: false)
        if status == "macOS denied keyboard access" {
            add("Keyboard access settings…", action: #selector(openKeyboardSettings))
        }
        menu.addItem(.separator())
        let sleepRow = NSView(frame: NSRect(x: 0, y: 0, width: 310, height: 38))
        let label = NSTextField(labelWithString: "Auto-sleep")
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.frame = NSRect(x: 14, y: 11, width: 95, height: 18)
        sleepRow.addSubview(label)
        let value = NSTextField(labelWithString: sleepLabel)
        value.font = .systemFont(ofSize: 12)
        value.textColor = .labelColor
        value.alignment = .right
        value.frame = NSRect(x: 105, y: 11, width: 140, height: 18)
        sleepRow.addSubview(value)
        let toggle = NSSwitch(frame: NSRect(x: 257, y: 7, width: 40, height: 24))
        toggle.state = sleepSetting == .on ? .on : sleepSetting == .off ? .off : .mixed
        toggle.isEnabled = operation == .idle && sleepSetting != nil
        toggle.target = self
        toggle.action = #selector(toggleSleep(_:))
        toggle.setAccessibilityLabel("Auto-sleep")
        toggle.setAccessibilityHelp("Turning auto-sleep on or off briefly reconnects the keyboard.")
        sleepRow.addSubview(toggle)
        add("Auto-sleep").view = sleepRow
        add(sleepMessage, enabled: false)
        menu.addItem(.separator())
        add(operation == .refreshing ? "Refreshing…" : "Refresh", action: #selector(refresh), enabled: operation == .idle)
        add(alertStatus, enabled: false)
        let warningItem = add(canNotify ? "Battery warnings" : "Enable battery notifications…", action: #selector(toggleWarnings))
        warningItem.state = canNotify && enabledWarnings ? .on : .off
        add("Notification settings…", action: #selector(openNotificationSettings))
        if let percent, percent <= 20 {
            add(percent <= 10 ? "Very low battery. Charge now." : "Low battery. Charge soon.", enabled: false)
        }
        if let lastWarningError { add(lastWarningError, enabled: false) }
        let loginItem = add("Launch at login", action: #selector(toggleLogin))
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        if SMAppService.mainApp.status == .requiresApproval { add("Allow login item in System Settings", enabled: false) }
        menu.addItem(.separator())
        add("Quit Keychron Menu", action: #selector(quit), enabled: !operation.isChanging)
        let diagnostic: [String: Any] = [
            "status": status, "percent": percent as Any? ?? NSNull(),
            "readAt": measuredAt?.ISO8601Format() as Any? ?? NSNull(),
            "notificationsAllowed": canNotify, "warningsEnabled": enabledWarnings,
            "notificationStatus": alertStatus,
            "sleep": sleepSetting?.rawValue as Any? ?? NSNull(),
            "sleepSource": sleepSetting == nil ? NSNull() : "keyboardReadback" as Any,
            "sleepLabel": sleepLabel, "sleepMessage": sleepMessage,
            "changingSleep": operation.isChanging,
            "processID": ProcessInfo.processInfo.processIdentifier
        ]
        if let data = try? JSONSerialization.data(withJSONObject: diagnostic, options: [.prettyPrinted, .sortedKeys]) {
            let url = stateURL.deletingLastPathComponent().appendingPathComponent("status.json")
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: url, options: .atomic)
        }
    }

    @discardableResult private func add(_ title: String, action: Selector? = nil, enabled: Bool = true) -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: action, keyEquivalent: "")
        entry.target = self
        entry.isEnabled = enabled
        menu.addItem(entry)
        return entry
    }

    @objc private func quit() { NSApp.terminate(nil) }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        operation.isChanging ? .terminateCancel : .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        reader.stop()
        timer?.invalidate()
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        if let hidManager { IOHIDManagerUnscheduleFromRunLoop(hidManager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue) }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
        willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }
}

@main
enum KeychronMenu {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
