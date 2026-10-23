import Foundation

@MainActor final class TestHeartbeat { var fired = false }

@main
enum Checks {
    @MainActor static func main() throws {
        var history = WarningHistory()
        assert(history.pending(percent: 21) == nil)
        assert(history.pending(percent: 20) == .low)
        history.spend(.low)
        assert(history.pending(percent: 19) == nil)
        assert(history.pending(percent: 10) == .critical)
        history.spend(.critical)
        assert(history.pending(percent: 9) == nil)
        history = try JSONDecoder().decode(WarningHistory.self, from: JSONEncoder().encode(history))
        assert(history.pending(percent: 9) == nil, "Restart must not repeat a warning")
        history.rearm(percent: 15)
        assert(history.pending(percent: 10) == nil)
        history.rearm(percent: 16)
        assert(history.pending(percent: 10) == .critical)
        assert(history.pending(percent: 20) == nil)
        history.rearm(percent: 25)
        assert(history.pending(percent: 20) == nil)
        history.rearm(percent: 26)
        assert(history.pending(percent: 20) == .low)
        history = WarningHistory()
        assert(history.pending(percent: 9) == .critical)
        history.spend(.critical)
        assert(history.pending(percent: 19) == nil, "Critical-first reading consumes both warnings")
        for invalid in ["{}", "{\"version\":2,\"status\":\"disconnected\"}", "{\"version\":1,\"status\":\"fresh\"}", "{\"version\":1,\"status\":\"fresh\",\"percent\":101}", "{\"version\":1,\"status\":\"fresh\",\"percent\":-1}"] {
            assert((try? BatteryReply.parse(Data(invalid.utf8))) == nil)
        }
        assert((try? BatteryReply.parse(Data(repeating: 32, count: 4097))) == nil)
        for value in [0, 19, 100] {
            let json = Data("{\"version\":1,\"status\":\"fresh\",\"percent\":\(value)}".utf8)
            let reply = try BatteryReply.parse(json)
            assert(reply.percent == value)
        }
        print("PASS warning thresholds, hysteresis, restart persistence, critical-first, malformed readings")

        for invalid in ["{}", "{\"version\":1,\"status\":\"fresh\"}",
                        "{\"version\":1,\"status\":\"fresh\",\"sleep\":\"maybe\"}",
                        "{\"version\":1,\"status\":\"disconnected\",\"sleep\":\"off\"}",
                        "{\"version\":2,\"status\":\"fresh\",\"sleep\":\"off\"}"] {
            assert((try? SleepReply.parse(Data(invalid.utf8))) == nil)
        }
        let on = try SleepReply.parse(Data("{\"version\":1,\"status\":\"fresh\",\"sleep\":\"on\"}".utf8))
        assert(on.sleep == .on)
        let unknown = try SleepReply.parse(Data("{\"version\":1,\"status\":\"verificationFailed\"}".utf8))
        assert(unknown.sleep == nil)
        print("PASS verified sleep state parsing, unknown state, rejected stale/invalid state")

        let folder = URL(fileURLWithPath: CommandLine.arguments[1])
        let reader = ReaderProcess()
        var completed = false
        var busyRejected = false
        let heartbeat = TestHeartbeat()
        let timer = Timer.scheduledTimer(withTimeInterval: 0.03, repeats: false) { _ in
            Task { @MainActor in heartbeat.fired = true }
        }
        reader.read(executable: folder.appendingPathComponent("HangReader"), timeout: 0.15) { result in
            if case .success = result { fatalError("Hung helper must fail") }
            completed = true
        }
        reader.read(executable: folder.appendingPathComponent("ValidReader")) { result in
            if case .failure = result { busyRejected = true }
        }
        pump(until: { completed })
        timer.invalidate()
        assert(heartbeat.fired, "Main loop must stay responsive during hardware read")
        assert(!reader.isReading && busyRejected)
        completed = false
        reader.read(executable: folder.appendingPathComponent("ValidReader")) { result in
            guard case .success(let reply) = result, reply.percent == 19 else { fatalError("Must recover after timeout") }
            completed = true
        }
        pump(until: { completed })
        completed = false
        reader.read(executable: folder.appendingPathComponent("InvalidReader")) { result in
            if case .success = result { fatalError("Invalid helper reply must fail") }
            completed = true
        }
        pump(until: { completed })
        print("PASS timeout, responsive main loop, busy rejection, reaped child, recovery, invalid helper reply")
    }

    @MainActor private static func pump(until done: () -> Bool) {
        let deadline = Date().addingTimeInterval(5)
        while !done() && Date() < deadline {
            _ = RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        precondition(done(), "Test exceeded deadline")
    }
}
