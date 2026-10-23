import Foundation
import Darwin

@MainActor
final class ReaderProcess {
    private var process: Process?
    private var deadline: Timer?
    private var timedOut = false

    var isReading: Bool { process != nil }

    func read(executable: URL, timeout: TimeInterval = 5,
              completion: @escaping @MainActor (Result<BatteryReply, Error>) -> Void) {
        run(executable: executable, timeout: timeout) { result in
            completion(result.flatMap { data in Result { try BatteryReply.parse(data) } })
        }
    }

    func run(executable: URL, arguments: [String] = [], timeout: TimeInterval = 5,
             completion: @escaping @MainActor (Result<Data, Error>) -> Void) {
        guard process == nil else {
            completion(.failure(NSError(domain: "Keyboard is busy", code: 1)))
            return
        }
        let child = Process()
        let output = Pipe()
        child.executableURL = executable
        child.arguments = arguments
        child.standardOutput = output
        child.standardError = FileHandle.nullDevice
        timedOut = false
        child.terminationHandler = { [weak self] finished in
            Task { @MainActor in
                guard let self, self.process === finished else { return }
                self.deadline?.invalidate()
                self.deadline = nil
                self.process = nil
                defer { try? output.fileHandleForReading.close() }
                if self.timedOut {
                    completion(.failure(NSError(domain: "Keyboard read timed out", code: 1)))
                } else if finished.terminationStatus != 0 {
                    completion(.failure(NSError(domain: "Keyboard helper failed", code: Int(finished.terminationStatus))))
                } else {
                    do {
                        let data = try output.fileHandleForReading.read(upToCount: 4097) ?? Data()
                        completion(.success(data))
                    } catch { completion(.failure(error)) }
                }
            }
        }
        process = child
        do { try child.run() }
        catch { process = nil; completion(.failure(error)); return }
        deadline = Timer(timeInterval: timeout, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, let child = self.process, child.isRunning else { return }
                self.timedOut = true
                kill(child.processIdentifier, SIGKILL)
            }
        }
        RunLoop.main.add(deadline!, forMode: .common)
    }

    func stop() {
        deadline?.invalidate()
        deadline = nil
        if let process, process.isRunning { kill(process.processIdentifier, SIGKILL) }
        process = nil
    }
}
