import Foundation
import SwiftUI

struct HistoryView: View {
    @ObservedObject var historyStore: WorkoutHistoryStore
    let profiles: [Profile]
    let activeProfileId: UUID?

    @State private var showActiveOnly: Bool = true

    var body: some View {
        NavigationStack {
            List {
                if activeProfileId != nil {
                    Section {
                        Toggle("Active profile only", isOn: $showActiveOnly)
                    }
                }

                if filteredWorkouts.isEmpty {
                    ContentUnavailableView(
                        "No workouts yet",
                        systemImage: "clock",
                        description: Text("Complete a ride to see it here.")
                    )
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(filteredWorkouts) { record in
                        HistoryWorkoutRow(
                            record: record,
                            profileName: profileName(for: record.profileId)
                        )
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                    .onDelete(perform: delete)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .navigationTitle("History")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    EditButton()
                }
            }
            .background(RideTheme.background)
        }
    }

    private var filteredWorkouts: [WorkoutRecord] {
        guard showActiveOnly, let activeProfileId else { return historyStore.workouts }
        return historyStore.workouts.filter { $0.profileId == activeProfileId }
    }

    private func profileName(for id: UUID?) -> String? {
        guard let id else { return nil }
        return profiles.first(where: { $0.id == id })?.name
    }

    private func delete(at offsets: IndexSet) {
        let ids = offsets.map { filteredWorkouts[$0].id }
        historyStore.delete(ids: ids)
    }
}

private struct HistoryWorkoutRow: View {
    let record: WorkoutRecord
    let profileName: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(dateLabel)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                Spacer()
                Text(distanceLabel)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(RideTheme.accent)
            }

            HStack(spacing: 8) {
                Text(durationLabel)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                if let profileName {
                    Text("|")
                        .foregroundStyle(.secondary)
                    Text(profileName)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }

            if let trackName = record.trackName, let trackDistance = record.trackDistanceKm {
                HStack(spacing: 8) {
                    Text("Track: \(trackName)")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("\(String(format: "%.1f km", trackDistance))")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                if let trackProgress = record.trackProgressMeters, trackProgress > 0, trackProgress < (trackDistance * 1000.0) {
                    Text("\(String(format: "%.1f km", trackProgress / 1000.0)) ridden on track")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                if let trackCompleted = record.trackCompleted {
                    Text(trackCompleted ? "Completed" : "Incomplete")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(trackCompleted ? Color.green : Color.orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(RideTheme.surface(trackCompleted ? Color.green : Color.orange, opacity: 0.18))
                        )
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(RideTheme.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    private var dateLabel: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: record.startDate)
    }

    private var durationLabel: String {
        let totalSeconds = max(0, Int(record.elapsedSeconds.rounded()))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "Duration %02d:%02d", minutes, seconds)
    }

    private var distanceLabel: String {
        let km = record.distanceMeters / 1000.0
        return String(format: "%.2f km", km)
    }
}
