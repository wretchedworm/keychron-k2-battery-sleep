import Foundation

enum SleepSetting: String, Decodable, Sendable {
    case on, off
    var title: String { rawValue.uppercased() }
    var opposite: SleepSetting { self == .on ? .off : .on }
}

struct SleepReply: Decodable, Sendable {
    let version: Int
    let status: String
    let sleep: SleepSetting?

    static func parse(_ data: Data) throws -> SleepReply {
        guard data.count <= 4096 else { throw ReaderError.invalidReply }
        let reply = try JSONDecoder().decode(SleepReply.self, from: data)
        guard reply.version == 1,
              ["fresh", "disconnected", "unsupported", "ambiguous", "accessDenied", "readFailure", "verificationFailed", "busy"].contains(reply.status),
              (reply.status == "fresh") == (reply.sleep != nil)
        else { throw ReaderError.invalidReply }
        return reply
    }
}

enum KeyboardOperation: Equatable {
    case idle, refreshing, changing(SleepSetting)
    var isChanging: Bool {
        if case .changing = self { return true }
        return false
    }
}
