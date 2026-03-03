import SwiftUI

// MARK: - Persisted Models (Codable snapshots of in-memory circle data)

struct PersistedCircle: Codable {
    let serverId: String
    var displayName: String
    var members: [PersistedMember]
    var splitMethod: String
    var leaderId: String?
}

struct PersistedMember: Codable {
    let name: String
    let initial: String
    let colorName: String
    var splitPercentage: Double
}

// MARK: - Color mapping

extension PersistedMember {
    private static let colorMap: [(name: String, color: Color)] = [
        ("red",    .red),
        ("orange", .orange),
        ("yellow", .yellow),
        ("green",  .green),
        ("blue",   .blue),
        ("purple", .purple),
        ("pink",   .pink),
        ("cyan",   .cyan),
        ("brown",  .brown),
        ("mint",   .mint),
        ("teal",   .teal),
        ("indigo", .indigo),
    ]

    init(from member: CircleMember) {
        self.name = member.name
        self.initial = member.initial
        self.colorName = Self.colorMap.first(where: { $0.color == member.color })?.name ?? "blue"
        self.splitPercentage = member.splitPercentage
    }

    func toCircleMember() -> CircleMember {
        let color = Self.colorMap.first(where: { $0.name == colorName })?.color ?? .blue
        var m = CircleMember(name: name, initial: initial, color: color)
        m.splitPercentage = splitPercentage
        return m
    }
}

// MARK: - CircleStore

/// Persists circle metadata (members, display name, split mode, leader) to UserDefaults.
/// Data the API doesn't return is preserved here across app launches.
enum CircleStore {
    private static let key = "tally.persistedCircles"

    static func loadAll() -> [String: PersistedCircle] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let dict = try? JSONDecoder().decode([String: PersistedCircle].self, from: data)
        else { return [:] }
        return dict
    }

    static func save(_ circle: PersistedCircle) {
        var all = loadAll()
        all[circle.serverId] = circle
        persist(all)
    }

    static func remove(serverId: String) {
        var all = loadAll()
        all.removeValue(forKey: serverId)
        persist(all)
    }

    private static func persist(_ dict: [String: PersistedCircle]) {
        if let data = try? JSONEncoder().encode(dict) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

// MARK: - Conversion helpers

extension PersistedCircle {
    init(from circle: TallyCircle) {
        self.serverId = circle.serverId ?? ""
        self.displayName = circle.name
        self.members = circle.members.map { PersistedMember(from: $0) }
        self.splitMethod = circle.splitMethod.rawValue
        self.leaderId = circle.leaderId?.uuidString
    }

    /// Merges persisted data into an API-sourced circle (which has empty members, default split, etc.)
    func apply(to circle: inout TallyCircle) {
        circle.name = displayName
        circle.members = members.map { $0.toCircleMember() }
        circle.splitMethod = SplitMethod(rawValue: splitMethod) ?? .equal
        circle.leaderId = leaderId.flatMap { UUID(uuidString: $0) }
    }
}
