//
//  PseudoTVScheduleStore.swift
//  EclipsePlexClient
//

import Foundation

/// Persists channels and weekly schedule snapshots under Application Support.
enum PseudoTVScheduleStore {
    private static let appFolderName = "PseudoTV"

    static func baseURL() throws -> URL {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = support.appendingPathComponent(appFolderName, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func channelsURL(serverId: UUID) throws -> URL {
        try baseURL().appendingPathComponent("channels-\(serverId.uuidString).json")
    }

    static func scheduleURL(channelId: String) throws -> URL {
        let safe = channelId.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? channelId
        return try baseURL().appendingPathComponent("schedule-\(safe).json")
    }

    static func loadChannels(serverId: UUID) -> [PseudoTVChannel] {
        guard let url = try? channelsURL(serverId: serverId),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([PseudoTVChannel].self, from: data)
        else { return [] }
        return decoded
    }

    static func saveChannels(_ channels: [PseudoTVChannel], serverId: UUID) {
        guard let url = try? channelsURL(serverId: serverId),
              let data = try? JSONEncoder().encode(channels)
        else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func loadSchedule(channelId: String) -> PseudoTVScheduleSnapshot? {
        guard let url = try? scheduleURL(channelId: channelId),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(PseudoTVScheduleSnapshot.self, from: data)
        else { return nil }
        return decoded
    }

    static func saveSchedule(_ snapshot: PseudoTVScheduleSnapshot) {
        guard let url = try? scheduleURL(channelId: snapshot.channelId),
              let data = try? JSONEncoder().encode(snapshot)
        else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func deleteSchedules(forServer serverId: UUID) {
        guard let base = try? baseURL() else { return }
        let prefix = "schedule-\(serverId.uuidString)"
        guard let files = try? FileManager.default.contentsOfDirectory(at: base, includingPropertiesForKeys: nil) else {
            return
        }
        for file in files where file.lastPathComponent.contains(prefix) || file.lastPathComponent.hasPrefix("schedule-") {
            try? FileManager.default.removeItem(at: file)
        }
    }
}
