//
//  PseudoTVChannelFactory.swift
//  EclipsePlexClient
//

import Foundation

enum PseudoTVChannelFactory {
    private static let minPoolSize = 6
    private static let maxChannels = 48

    static func makeChannels(serverId: UUID, index: PseudoTVLibraryIndex) -> [PseudoTVChannel] {
        var channels: [PseudoTVChannel] = []
        var seen = Set<String>()

        func add(_ name: String, kind: PseudoTVGroupingKind, key: String, mode: PseudoTVContentMode) {
            guard channels.count < maxChannels else { return }
            let id = PseudoTVChannel.makeID(serverId: serverId, kind: kind, key: key)
            guard seen.insert(id).inserted else { return }
            channels.append(PseudoTVChannel(
                id: id,
                serverId: serverId,
                name: name,
                groupingKind: kind,
                groupingKey: key,
                contentMode: mode,
                isHidden: false,
                cycleGeneration: 0
            ))
        }

        let librariesTV = Set(index.episodes.map(\.libraryTitle))
        for title in librariesTV.sorted() {
            let pool = index.episodes.filter { $0.libraryTitle == title }
            guard pool.count >= minPoolSize else { continue }
            add("TV: \(title)", kind: .librarySection, key: "tv|\(title)", mode: .tvOnly)
        }

        let librariesMovies = Set(index.movies.map(\.libraryTitle))
        for title in librariesMovies.sorted() {
            let pool = index.movies.filter { $0.libraryTitle == title }
            guard pool.count >= minPoolSize else { continue }
            add("Movies: \(title)", kind: .librarySection, key: "movies|\(title)", mode: .moviesOnly)
        }

        for decade in decades(from: index.movies.compactMap(\.year)) {
            let pool = index.movies.filter { decade.contains($0.year) }
            guard pool.count >= minPoolSize else { continue }
            add("Movies: \(decade.label)", kind: .decade, key: "movies|\(decade.label)", mode: .moviesOnly)
        }

        for decade in decades(from: index.episodes.compactMap(\.year)) {
            let pool = index.episodes.filter { decade.contains($0.year) }
            guard pool.count >= minPoolSize else { continue }
            add("TV: \(decade.label)", kind: .decade, key: "tv|\(decade.label)", mode: .tvOnly)
        }

        for genre in topKeys(index.movies.flatMap(\.genres), limit: 12) {
            let pool = index.movies.filter { $0.genres.contains(genre) }
            guard pool.count >= minPoolSize else { continue }
            add("Movies: \(genre)", kind: .movieGenre, key: genre, mode: .moviesOnly)
        }

        for genre in topKeys(index.episodes.flatMap(\.genres), limit: 12) {
            let pool = index.episodes.filter { $0.genres.contains(genre) }
            guard pool.count >= minPoolSize else { continue }
            add("TV: \(genre)", kind: .tvGenre, key: genre, mode: .tvOnly)
        }

        for network in topKeys(index.episodes.compactMap(\.network), limit: 10) {
            let pool = index.episodes.filter { $0.network == network }
            guard pool.count >= minPoolSize else { continue }
            add("Network: \(network)", kind: .network, key: network, mode: .tvOnly)
        }

        return channels
    }

    static func programs(
        for channel: PseudoTVChannel,
        index: PseudoTVLibraryIndex
    ) -> [PseudoTVProgramRef] {
        switch channel.groupingKind {
        case .librarySection:
            if channel.groupingKey.hasPrefix("tv|") {
                let title = String(channel.groupingKey.dropFirst(3))
                return orderedEpisodes(
                    index.episodes.filter { $0.libraryTitle == title }.map(\.program),
                    recentKeys: index.recentEpisodeKeys
                )
            }
            if channel.groupingKey.hasPrefix("movies|") {
                let title = String(channel.groupingKey.dropFirst(7))
                return index.movies.filter { $0.libraryTitle == title }.map(\.program).shuffled()
            }
        case .decade:
            if channel.groupingKey.hasPrefix("movies|") {
                let label = String(channel.groupingKey.dropFirst(7))
                let decade = DecadeLabel(parsedLabel: label)
                return index.movies.filter { decade.contains($0.year) }.map(\.program).shuffled()
            }
            if channel.groupingKey.hasPrefix("tv|") {
                let label = String(channel.groupingKey.dropFirst(3))
                let decade = DecadeLabel(parsedLabel: label)
                return orderedEpisodes(
                    index.episodes.filter { decade.contains($0.year) }.map(\.program),
                    recentKeys: index.recentEpisodeKeys
                )
            }
        case .movieGenre:
            return index.movies.filter { $0.genres.contains(channel.groupingKey) }.map(\.program).shuffled()
        case .tvGenre:
            return orderedEpisodes(
                index.episodes.filter { $0.genres.contains(channel.groupingKey) }.map(\.program),
                recentKeys: index.recentEpisodeKeys
            )
        case .network:
            return orderedEpisodes(
                index.episodes.filter { $0.network == channel.groupingKey }.map(\.program),
                recentKeys: index.recentEpisodeKeys
            )
        }
        return []
    }

    private static func orderedEpisodes(
        _ programs: [PseudoTVProgramRef],
        recentKeys: Set<String>
    ) -> [PseudoTVProgramRef] {
        let recent = programs.filter { recentKeys.contains($0.ratingKey) }
        let rest = programs.filter { !recentKeys.contains($0.ratingKey) }
        return recent + rest
    }

    private static func topKeys(_ values: [String], limit: Int) -> [String] {
        var counts: [String: Int] = [:]
        for v in values where !v.isEmpty {
            counts[v, default: 0] += 1
        }
        return counts.sorted { $0.value > $1.value }.prefix(limit).map(\.key)
    }

    private static func decades(from years: [Int]) -> [DecadeLabel] {
        let buckets = Set(years.map { DecadeLabel.from(year: $0) })
        return buckets.sorted { $0.startYear < $1.startYear }
    }
}

private struct DecadeLabel: Hashable {
    let label: String
    let startYear: Int

    init(parsedLabel: String) {
        label = parsedLabel
        let digits = parsedLabel.filter(\.isNumber)
        startYear = Int(digits) ?? 1990
    }

    static func from(year: Int) -> DecadeLabel {
        let start = (year / 10) * 10
        return DecadeLabel(parsedLabel: "\(start)s")
    }

    func contains(_ year: Int?) -> Bool {
        guard let year else { return false }
        return year >= startYear && year < startYear + 10
    }
}
