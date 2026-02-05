import SwiftUI

struct HistoryView: View {
    @ObservedObject var store: WorkoutHistoryStore
    let distanceUnit: String
    let activeProfile: Profile?

    var body: some View {
        NavigationStack {
            List {
                if let activeProfile {
                    let records = store.workouts.filter { $0.profileId == activeProfile.id }
                    if records.isEmpty {
                        ContentUnavailableView(
                            "No workouts yet",
                            systemImage: "clock",
                            description: Text("Finish a ride for \(activeProfile.name).")
                        )
                    } else {
                        ForEach(records) { record in
                            NavigationLink(value: record.id) {
                                WorkoutRow(record: record, distanceUnit: distanceUnit)
                            }
                        }
                        .onDelete { offsets in
                            let ids = offsets.map { records[$0].id }
                            store.delete(ids: ids)
                        }
                    }
                } else {
                    ContentUnavailableView(
                        "Select a profile",
                        systemImage: "person.crop.circle",
                        description: Text("Choose a profile to view workout history.")
                    )
                }
            }
            .navigationTitle("History")
            .navigationDestination(for: UUID.self) { recordID in
                if let record = store.workouts.first(where: { $0.id == recordID }) {
                    WorkoutDetailView(record: record, distanceUnit: distanceUnit)
                } else {
                    Text("Workout not found")
                        .foregroundStyle(.secondary)
                }
            }
            .toolbar {
                EditButton()
            }
        }
    }
}

private struct WorkoutRow: View {
    let record: WorkoutRecord
    let distanceUnit: String

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(DateFormatter.workoutDate.string(from: record.startDate))
                    .font(.system(size: 16, weight: .semibold))
                Text(timeText)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(distanceText)
                    .font(.system(size: 16, weight: .semibold))
                Text(speedText)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }

    private var timeText: String {
        DateComponentsFormatter.workoutDuration.string(from: record.elapsedSeconds) ?? "--:--"
    }

    private var distanceText: String {
        let value = distanceUnit == "mi"
            ? record.distanceMeters / 1609.344
            : record.distanceMeters / 1000.0
        let unit = distanceUnit == "mi" ? "mi" : "km"
        return String(format: "%.2f %@", value, unit)
    }

    private var speedText: String {
        guard record.elapsedSeconds > 0 else { return "0.0 \(speedUnit)" }
        let kph = (record.distanceMeters / record.elapsedSeconds) * 3.6
        let value = distanceUnit == "mi" ? kph / 1.609344 : kph
        return String(format: "Avg %.1f %@", value, speedUnit)
    }

    private var speedUnit: String {
        distanceUnit == "mi" ? "mph" : "km/h"
    }
}

private struct WorkoutDetailView: View {
    let record: WorkoutRecord
    let distanceUnit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(DateFormatter.workoutDateTime.string(from: record.startDate))
                    .font(.system(size: 22, weight: .semibold))
                Text("Finished \(DateFormatter.workoutTime.string(from: record.endDate))")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 16) {
                DetailMetric(title: "Duration", value: durationText)
                DetailMetric(title: "Distance", value: distanceText)
                DetailMetric(title: "Avg Speed", value: speedText)
            }

            Spacer()
        }
        .padding(24)
        .navigationTitle("Workout")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var durationText: String {
        DateComponentsFormatter.workoutDuration.string(from: record.elapsedSeconds) ?? "--:--"
    }

    private var distanceText: String {
        let value = distanceUnit == "mi"
            ? record.distanceMeters / 1609.344
            : record.distanceMeters / 1000.0
        let unit = distanceUnit == "mi" ? "mi" : "km"
        return String(format: "%.2f %@", value, unit)
    }

    private var speedText: String {
        guard record.elapsedSeconds > 0 else { return "0.0 \(speedUnit)" }
        let kph = (record.distanceMeters / record.elapsedSeconds) * 3.6
        let value = distanceUnit == "mi" ? kph / 1.609344 : kph
        return String(format: "%.1f %@", value, speedUnit)
    }

    private var speedUnit: String {
        distanceUnit == "mi" ? "mph" : "km/h"
    }
}

private struct DetailMetric: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 20, weight: .semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemBackground))
        )
    }
}

private extension DateFormatter {
    static let workoutDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    static let workoutDateTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    static let workoutTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()
}

private extension DateComponentsFormatter {
    static let workoutDuration: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.zeroFormattingBehavior = [.pad]
        return formatter
    }()
}
