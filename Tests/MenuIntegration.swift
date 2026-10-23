import AppKit

@main
@MainActor
enum MenuIntegration {
    static var phase = 0
    static var started = Date()
    static var timer: Timer?
    static let delegate = AppDelegate()

    static func fail(_ message: String) -> Never {
        print("FAIL \(message)")
        fflush(stdout)
        exit(1)
    }

    static func switchControl() -> NSSwitch {
        let controls = delegate.menu.items.compactMap(\.view).flatMap(\.subviews).compactMap { $0 as? NSSwitch }
        guard controls.count == 1, let control = controls.first, control.action != nil,
              control.target === delegate else { fail("Exactly one wired auto-sleep switch required") }
        return control
    }

    static func click(_ expected: SleepSetting) {
        let control = switchControl()
        guard control.isEnabled, control.state == (expected == .on ? .on : .off) else { fail("Switch must represent actual state") }
        control.performClick(nil)
        guard delegate.operation == .changing(expected.opposite), delegate.sleepSetting == nil,
              !switchControl().isEnabled else { fail("Changing must disable switch and clear unconfirmed state") }
        guard delegate.applicationShouldTerminate(NSApp) == .terminateCancel else { fail("Quit must not interrupt change") }
    }

    static func poll() {
        if Date().timeIntervalSince(started) > 100 { fail("Integration deadline") }
        guard delegate.operation == .idle else { return }
        switch phase {
        case 0:
            guard delegate.sleepSetting == .off else { fail("Initial real state must be OFF: \(delegate.sleepMessage)") }
            print("PASS initial real OFF, wired enabled menu switch")
            phase = 1
            click(.off)
        case 1:
            guard delegate.sleepSetting == .on else { fail("ON not confirmed: \(delegate.sleepMessage)") }
            print("PASS menu action ON, restart and actual readback")
            phase = 2
            click(.on)
        case 2:
            guard delegate.sleepSetting == .off else { fail("OFF not confirmed: \(delegate.sleepMessage)") }
            guard switchControl().state == .off, switchControl().isEnabled else { fail("Final switch state") }
            let titles = delegate.menu.items.map(\.title).joined(separator: " ")
            guard !titles.contains("idle"), !titles.contains("Record"), !titles.contains("Likely") else { fail("Old inference UI remains") }
            guard delegate.applicationShouldTerminate(NSApp) == .terminateNow else { fail("Quit must recover") }
            print("PASS menu action OFF, restart and actual readback; clean menu and normal quit restored")
            fflush(stdout)
            exit(0)
        default: break
        }
        fflush(stdout)
    }

    static func main() {
        let app = NSApplication.shared
        app.delegate = delegate
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            Task { @MainActor in poll() }
        }
        app.run()
    }
}
