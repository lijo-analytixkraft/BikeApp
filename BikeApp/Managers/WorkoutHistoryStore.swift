import Combine
import Foundation

struct WorkoutRecord: Identifiable, Codable {
    let id: UUID
    let profileId: UUID?
    let startDate: Date
    let endDate: Date
    let distanceMeters: Double
    let elapsedSeconds: TimeInterval
    let trackId: UUID?
    let trackName: String?
    let trackDistanceKm: Double?
    let trackProgressMeters: Double?
    let trackCompleted: Bool?
}

@MainActor
final class WorkoutHistoryStore: ObservableObject {
    @Published private(set) var workouts: [WorkoutRecord] = []

    private let fileURL: URL

    init() {
        fileURL = Self.historyFileURL()
        load()
    }

    func add(
        summary: WorkoutSummary,
        profileId: UUID,
        trackId: UUID? = nil,
        trackName: String? = nil,
        trackDistanceKm: Double? = nil,
        trackProgressMeters: Double? = nil,
        trackCompleted: Bool? = nil
    ) {
        let record = WorkoutRecord(
            id: UUID(),
            profileId: profileId,
            startDate: summary.startDate,
            endDate: summary.endDate,
            distanceMeters: summary.distanceMeters,
            elapsedSeconds: summary.elapsedSeconds,
            trackId: trackId,
            trackName: trackName,
            trackDistanceKm: trackDistanceKm,
            trackProgressMeters: trackProgressMeters,
            trackCompleted: trackCompleted
        )
        workouts.insert(record, at: 0)
        save()
    }

    func delete(at offsets: IndexSet) {
        for offset in offsets.sorted(by: >) {
            workouts.remove(at: offset)
        }
        save()
    }

    func delete(ids: [UUID]) {
        let idSet = Set(ids)
        workouts.removeAll { idSet.contains($0.id) }
        save()
    }

    func clear() {
        workouts.removeAll()
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let decoded = try? decoder.decode([WorkoutRecord].self, from: data) {
            workouts = decoded
        }
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(workouts) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private static func historyFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("BikeApp", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("workout-history.json")
    }
}

struct Profile: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var colorHex: UInt32?
    var iconName: String?
    var targetDistanceKm: Double?
    let createdAt: Date
}

@MainActor
final class ProfileStore: ObservableObject {
    @Published private(set) var profiles: [Profile] = []
    @Published private(set) var activeProfileId: UUID?

    private let fileURL: URL
    private let activeProfileKey = "activeProfileId"
    private let palette: [UInt32] = [
        0xF06010, 0x1F8EFA, 0x2BD0C8, 0x31C48D, 0xF5A524, 0xD64550
    ]

    init() {
        fileURL = Self.profileFileURL()
        load()
        loadActiveProfile()
    }

    var activeProfile: Profile? {
        guard let activeProfileId else { return nil }
        return profiles.first { $0.id == activeProfileId }
    }

    func addProfile(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let profile = Profile(
            id: UUID(),
            name: trimmed,
            colorHex: nextColorHex(),
            iconName: nil,
            targetDistanceKm: nil,
            createdAt: Date()
        )
        profiles.append(profile)
        profiles = sortProfiles(profiles)
        save()
    }

    func updateProfile(id: UUID, name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = profiles.firstIndex(where: { $0.id == id }) else { return }
        profiles[index].name = trimmed
        save()
    }

    func updateProfileTargetDistance(id: UUID, targetKm: Double?) {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { return }
        profiles[index].targetDistanceKm = targetKm
        save()
    }

    func deleteProfile(id: UUID) {
        profiles.removeAll { $0.id == id }
        if activeProfileId == id {
            clearActiveProfile()
        }
        save()
    }

    func setActiveProfile(_ profile: Profile) {
        activeProfileId = profile.id
        saveActiveProfile()
    }

    func clearActiveProfile() {
        activeProfileId = nil
        saveActiveProfile()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let decoded = try? decoder.decode([Profile].self, from: data) {
            profiles = decoded
        }
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(profiles) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private func loadActiveProfile() {
        let stored = UserDefaults.standard.string(forKey: activeProfileKey)
        if let stored, let uuid = UUID(uuidString: stored), profiles.contains(where: { $0.id == uuid }) {
            activeProfileId = uuid
        } else {
            activeProfileId = nil
        }
    }

    private func saveActiveProfile() {
        if let activeProfileId {
            UserDefaults.standard.set(activeProfileId.uuidString, forKey: activeProfileKey)
        } else {
            UserDefaults.standard.removeObject(forKey: activeProfileKey)
        }
    }

    private func sortProfiles(_ profiles: [Profile]) -> [Profile] {
        profiles.sorted { lhs, rhs in
            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt < rhs.createdAt
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private func nextColorHex() -> UInt32 {
        let index = profiles.count % palette.count
        return palette[index]
    }

    private static func profileFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("BikeApp", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("profiles.json")
    }
}

extension Profile {
    var initials: String {
        let parts = name.split(separator: " ").filter { !$0.isEmpty }
        let first = parts.first?.first.map { String($0) } ?? ""
        let second = parts.dropFirst().first?.first.map { String($0) } ?? ""
        let combined = (first + second).uppercased()
        return combined.isEmpty ? "?" : combined
    }
}
