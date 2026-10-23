import Foundation

struct BatteryReply: Decodable, Sendable {
    let version: Int
    let status: String
    let percent: Int?

    static func parse(_ data: Data) throws -> BatteryReply {
        guard data.count <= 4096 else { throw ReaderError.invalidReply }
        let reply = try JSONDecoder().decode(BatteryReply.self, from: data)
        let statuses = ["fresh", "disconnected", "unsupported", "ambiguous", "accessDenied", "readFailure", "invalidReport"]
        guard reply.version == 1, statuses.contains(reply.status),
              reply.status != "fresh" || (reply.percent.map { (0...100).contains($0) } ?? false)
        else { throw ReaderError.invalidReply }
        return reply
    }
}

enum ReaderError: Error { case invalidReply }
enum BatteryWarning: String, Codable { case low, critical }

struct WarningHistory: Codable, Equatable {
    var lowSpent = false
    var criticalSpent = false

    mutating func rearm(percent: Int) {
        if percent > 25 { lowSpent = false }
        if percent > 15 { criticalSpent = false }
    }

    func pending(percent: Int) -> BatteryWarning? {
        if percent <= 10 { return criticalSpent ? nil : .critical }
        return percent <= 20 && !lowSpent ? .low : nil
    }

    mutating func spend(_ warning: BatteryWarning) {
        lowSpent = true
        if warning == .critical { criticalSpent = true }
    }
}
