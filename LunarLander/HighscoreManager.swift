//
//  HighscoreManager.swift
//  LunarLander
//
//  Highscore data model and JSON persistence
//

import Foundation

struct HighscoreEntry: Codable {
    let name: String
    let score: Int
    let level: Int
}

struct HighscoreTable: Codable {
    var entries: [HighscoreEntry]

    static let maxEntries = 10

    static func defaultTable() -> HighscoreTable {
        let defaults: [(String, Int, Int)] = [
            ("NEIL",    5000, 5),
            ("BUZZ",    4200, 4),
            ("MICHAEL", 3500, 4),
            ("PETE",    2800, 3),
            ("ALAN",    2200, 3),
            ("JOHN",    1800, 2),
            ("JIM",     1400, 2),
            ("GENE",    1000, 1),
            ("SALLY",    700, 1),
            ("MAE",      400, 1),
        ]
        return HighscoreTable(entries: defaults.map {
            HighscoreEntry(name: $0.0, score: $0.1, level: $0.2)
        })
    }

    var lowestScore: Int {
        return entries.last?.score ?? 0
    }

    mutating func insert(_ entry: HighscoreEntry) {
        entries.append(entry)
        entries.sort { $0.score > $1.score }
        if entries.count > Self.maxEntries {
            entries = Array(entries.prefix(Self.maxEntries))
        }
    }

    func qualifies(score: Int) -> Bool {
        return entries.count < Self.maxEntries || score > lowestScore
    }
}

class HighscoreManager {
    static let shared = HighscoreManager()

    private let directoryPath: String
    private let filePath: String
    var table: HighscoreTable

    private init() {
        #if os(iOS)
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!.path
        directoryPath = "\(docs)/LunarLander"
        #else
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        directoryPath = "\(home)/.lunarlander"
        #endif
        filePath = "\(directoryPath)/highscores.json"
        table = HighscoreManager.load(from: filePath) ?? HighscoreTable.defaultTable()
    }

    private static func load(from path: String) -> HighscoreTable? {
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        return try? JSONDecoder().decode(HighscoreTable.self, from: data)
    }

    func save() {
        let fm = FileManager.default
        if !fm.fileExists(atPath: directoryPath) {
            try? fm.createDirectory(atPath: directoryPath,
                                    withIntermediateDirectories: true)
        }
        if let data = try? JSONEncoder().encode(table) {
            fm.createFile(atPath: filePath, contents: data)
        }
    }

    func addEntry(name: String, score: Int, level: Int) {
        let entry = HighscoreEntry(name: name, score: score, level: level)
        table.insert(entry)
        save()
    }

    func qualifies(score: Int) -> Bool {
        return table.qualifies(score: score)
    }
}
