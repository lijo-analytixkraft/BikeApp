import Combine
import SwiftUI
import UIKit

enum AppSection: String, CaseIterable, Identifiable {
    case workout
    case history
    case profiles

    var id: String { rawValue }

    var title: String {
        switch self {
        case .workout:
            return "Workout"
        case .history:
            return "History"
        case .profiles:
            return "Profiles"
        }
    }

    var systemImage: String {
        switch self {
        case .workout:
            return "bicycle"
        case .history:
            return "clock"
        case .profiles:
            return "person.2"
        }
    }
}

struct ContentView: View {
    @StateObject private var bluetooth = BluetoothManager()
    @StateObject private var workout = WorkoutSession()
    @StateObject private var healthKit = HealthKitManager()
    @StateObject private var historyStore = WorkoutHistoryStore()
    @ObservedObject var profileStore: ProfileStore

    private let healthKitWritesEnabled = false

    @AppStorage("distanceUnit") private var distanceUnit: String = "km"
    @AppStorage("useTransparentUI") private var useTransparentUI: Bool = true

    @State private var selection: AppSection? = .workout
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(selection: $selection) {
                Section {
                    ForEach(AppSection.allCases) { section in
                        Label(section.title, systemImage: section.systemImage)
                            .tag(section as AppSection?)
                    }
                }
                Section("Appearance") {
                    Toggle("Transparent UI", isOn: $useTransparentUI)
                }
                Section("Active Profile") {
                    ActiveProfileRow(profile: profileStore.activeProfile)
                        .allowsHitTesting(false)
                }
                Section("Connection") {
                    ConnectionStatusRow(isConnected: bluetooth.isConnected)
                        .allowsHitTesting(false)
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("BikeApp")
        } detail: {
            switch selection {
            case .workout:
                if let activeProfile = profileStore.activeProfile {
                    WorkoutDashboardView(
                        bluetooth: bluetooth,
                        workout: workout,
                        healthKit: healthKit,
                        historyStore: historyStore,
                        distanceUnit: $distanceUnit,
                        healthKitWritesEnabled: healthKitWritesEnabled,
                        activeProfileId: activeProfile.id,
                        activeProfileName: activeProfile.name,
                        activeProfileInitials: activeProfile.initials,
                        activeProfileColorHex: activeProfile.colorHex ?? RideTheme.accentHex,
                        targetDistanceKm: activeProfile.targetDistanceKm,
                        profiles: profileStore.profiles,
                        onSelectProfile: { profile in
                            profileStore.setActiveProfile(profile)
                        },
                        onAddProfile: { name in
                            profileStore.addProfile(name: name)
                        },
                        onUpdateTargetDistance: { targetKm in
                            profileStore.updateProfileTargetDistance(id: activeProfile.id, targetKm: targetKm)
                        }
                    )
                } else {
                    ProfileSelectionView(
                        store: profileStore,
                        selectionRequired: true
                    )
                }
            case .history:
                HistoryView(store: historyStore, distanceUnit: distanceUnit, activeProfile: profileStore.activeProfile)
            case .profiles:
                ProfileSelectionView(
                    store: profileStore,
                    selectionRequired: false
                )
            case .none:
                ContentUnavailableView("Select a section", systemImage: "sidebar.left")
            }
        }
        .onAppear {
            RideTheme.surfaceOpacity = useTransparentUI ? 0 : 1
        }
        .onChange(of: useTransparentUI) { _, newValue in
            RideTheme.surfaceOpacity = newValue ? 0 : 1
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    toggleSidebar()
                } label: {
                    Image(systemName: "sidebar.left")
                }
                .accessibilityLabel("Toggle Sidebar")
            }
        }
    }

    private func toggleSidebar() {
        withAnimation {
            columnVisibility = columnVisibility == .all ? .detailOnly : .all
        }
    }
}

struct WorkoutDashboardView: View {
    @ObservedObject var bluetooth: BluetoothManager
    @ObservedObject var workout: WorkoutSession
    @ObservedObject var healthKit: HealthKitManager
    @ObservedObject var historyStore: WorkoutHistoryStore
    @Binding var distanceUnit: String
    let healthKitWritesEnabled: Bool
    let activeProfileId: UUID
    let activeProfileName: String
    let activeProfileInitials: String
    let activeProfileColorHex: UInt32
    let targetDistanceKm: Double?
    let profiles: [Profile]
    let onSelectProfile: (Profile) -> Void
    let onAddProfile: (String) -> Void
    let onUpdateTargetDistance: (Double?) -> Void

    @Environment(\.scenePhase) private var scenePhase
    @State private var saveInProgress = false
    @State private var actionMessage: String = ""
    @State private var startDistanceMeters: Double = 0
    @State private var autoStopTriggered = false

    var body: some View {
        ZStack {
            CyclingBackground()
            RideDashboardView(
                appName: "BikeApp",
                profileName: activeProfileName,
                profileInitials: activeProfileInitials,
                profileColorHex: activeProfileColorHex,
                activeProfileId: activeProfileId,
                profiles: profiles,
                canChangeProfile: !workout.isActive,
                onSelectProfile: onSelectProfile,
                onAddProfile: onAddProfile,
                workoutState: workoutState,
                speedText: speedText,
                cadenceText: cadenceText,
                distanceText: distanceText,
                elapsedText: timeText,
                avgSpeedText: avgSpeedText,
                maxSpeedText: maxSpeedText,
                totalDistanceText: totalDistanceText,
                targetDistanceKm: targetDistanceKm,
                canEditTargetDistance: !workout.isActive,
                onUpdateTargetDistance: onUpdateTargetDistance,
                isConnected: bluetooth.isConnected,
                speedSamples: workout.speedSamples,
                isActive: workout.isActive,
                isPaused: workout.isPaused,
                onStart: startOrResume,
                onPause: pauseWorkout,
                onStop: stopWorkout
            )
        }
        .onReceive(bluetooth.$cadenceRpm.combineLatest(bluetooth.$speedKph, bluetooth.$hasSpeedReading)) { cadence, speed, hasSpeed in
            workout.updateMetrics(cadenceRpm: cadence, speedKph: hasSpeed ? speed : nil)
        }
        .onReceive(workout.$distanceMeters) { distanceMeters in
            checkAutoStop(distanceMeters: distanceMeters)
        }
        .onAppear {
            updateIdleTimer()
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .onChange(of: workout.isActive) { _, _ in
            updateIdleTimer()
        }
        .onChange(of: workout.isPaused) { _, _ in
            updateIdleTimer()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                workout.syncAfterAppBecameActive()
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .tint(RideTheme.accent)
    }

    private var cadenceText: String {
        String(format: "%.0f", workout.cadenceRpm)
    }

    private var timeText: String {
        let totalSeconds = max(0, Int(workout.elapsedSeconds.rounded()))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private var distanceText: String {
        let km = workout.distanceMeters / 1000.0
        return String(format: "%.2f", km)
    }

    private var speedText: String {
        String(format: "%.1f", workout.speedKph)
    }

    private var avgSpeedText: String {
        guard workout.elapsedSeconds > 0 else { return "0.0" }
        let avgKph = (workout.distanceMeters / workout.elapsedSeconds) * 3.6
        return String(format: "%.1f", avgKph)
    }

    private var maxSpeedText: String {
        let maxKph = workout.speedSamples.map(\.speedKph).max() ?? 0
        return String(format: "%.1f", maxKph)
    }

    private var totalDistanceText: String {
        let totalMeters = historyStore.workouts
            .filter { $0.profileId == activeProfileId }
            .reduce(0.0) { $0 + $1.distanceMeters }
        let km = totalMeters / 1000.0
        return String(format: "%.2f", km)
    }

    private var workoutState: WorkoutState {
        if workout.isPaused {
            return .paused
        }
        if workout.isActive {
            return .riding
        }
        return .ready
    }

    private func startOrResume() {
        actionMessage = ""
        if workout.isActive {
            if workout.isPaused {
                workout.resume()
            }
            return
        }
        autoStopTriggered = false
        startDistanceMeters = workout.distanceMeters
        if healthKitWritesEnabled {
            if healthKit.isAuthorized {
                workout.start()
            } else {
                healthKit.requestAuthorization { success in
                    if success {
                        workout.start()
                    } else {
                        actionMessage = "Health permission required to save workout"
                    }
                }
            }
        } else {
            workout.start()
        }
    }

    private func pauseWorkout() {
        workout.pause()
    }

    private func stopWorkout() {
        guard let summary = workout.stop() else { return }
        autoStopTriggered = false
        historyStore.add(summary: summary, profileId: activeProfileId)
        if healthKitWritesEnabled {
            saveInProgress = true
            healthKit.saveWorkout(
                startDate: summary.startDate,
                endDate: summary.endDate,
                distanceMeters: summary.distanceMeters
            ) { success in
                saveInProgress = false
                actionMessage = success ? "Workout saved" : "Workout save failed"
            }
        } else {
            actionMessage = "Workout complete (Health save disabled)"
        }
    }

    private func checkAutoStop(distanceMeters: Double) {
        guard workout.isActive, !autoStopTriggered else { return }
        guard let targetDistanceKm, targetDistanceKm > 0 else { return }
        let targetMeters = targetDistanceKm * 1000.0
        let traveledMeters = max(0, distanceMeters - startDistanceMeters)
        if traveledMeters >= targetMeters {
            autoStopTriggered = true
            stopWorkout()
        }
    }

    private func updateIdleTimer() {
        UIApplication.shared.isIdleTimerDisabled = workout.isActive && !workout.isPaused
    }
}

private struct RideDashboardView: View {
    let appName: String
    let profileName: String
    let profileInitials: String
    let profileColorHex: UInt32
    let activeProfileId: UUID
    let profiles: [Profile]
    let canChangeProfile: Bool
    let onSelectProfile: (Profile) -> Void
    let onAddProfile: (String) -> Void
    let workoutState: WorkoutState
    let speedText: String
    let cadenceText: String
    let distanceText: String
    let elapsedText: String
    let avgSpeedText: String
    let maxSpeedText: String
    let totalDistanceText: String
    let targetDistanceKm: Double?
    let canEditTargetDistance: Bool
    let onUpdateTargetDistance: (Double?) -> Void
    let isConnected: Bool
    let speedSamples: [SpeedSample]
    let isActive: Bool
    let isPaused: Bool
    let onStart: () -> Void
    let onPause: () -> Void
    let onStop: () -> Void

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let contentWidth = min(size.width * 0.92, 1200)

            VStack(spacing: 24) {
                TopBar(
                    appName: appName,
                    profileName: profileName,
                    profileInitials: profileInitials,
                    profileColorHex: profileColorHex,
                    activeProfileId: activeProfileId,
                    profiles: profiles,
                    canChangeProfile: canChangeProfile,
                    onSelectProfile: onSelectProfile,
                    onAddProfile: onAddProfile,
                    workoutState: workoutState,
                    isConnected: isConnected
                )

                MetricsRow(
                    speedText: speedText,
                    cadenceText: cadenceText,
                    distanceText: distanceText,
                    elapsedText: elapsedText
                )

                TargetDistanceBar(
                    targetDistanceKm: targetDistanceKm,
                    canEdit: canEditTargetDistance,
                    onUpdateTargetDistance: onUpdateTargetDistance
                )

                ControlRow(
                    isActive: isActive,
                    isPaused: isPaused,
                    onStart: onStart,
                    onPause: onPause,
                    onStop: onStop
                )

                GraphSection(speedSamples: speedSamples)

                BottomBar(
                    avgSpeedText: avgSpeedText,
                    maxSpeedText: maxSpeedText,
                    totalDistanceText: totalDistanceText
                )
            }
            .frame(maxWidth: contentWidth)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, max(24, size.width * 0.04))
            .padding(.vertical, max(24, size.height * 0.04))
        }
    }
}

private struct TopBar: View {
    let appName: String
    let profileName: String
    let profileInitials: String
    let profileColorHex: UInt32
    let activeProfileId: UUID
    let profiles: [Profile]
    let canChangeProfile: Bool
    let onSelectProfile: (Profile) -> Void
    let onAddProfile: (String) -> Void
    let workoutState: WorkoutState
    let isConnected: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                Text(appName)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)

                ProfileDropdown(
                    name: profileName,
                    initials: profileInitials,
                    colorHex: profileColorHex,
                    activeProfileId: activeProfileId,
                    profiles: profiles,
                    canChange: canChangeProfile,
                    onSelect: onSelectProfile,
                    onAdd: onAddProfile
                )
            }

            Spacer()

            Text(workoutState.rawValue)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(RideTheme.accent)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(RideTheme.surface(RideTheme.accent, opacity: 0.12))
                )

            Spacer()

            ConnectionIndicator(isConnected: isConnected)
        }
    }
}

private struct MetricsRow: View {
    let speedText: String
    let cadenceText: String
    let distanceText: String
    let elapsedText: String

    var body: some View {
        HStack(spacing: 11) {
            MetricCard(
                title: "Speed",
                value: speedText,
                unit: "km/h",
                isPrimary: true
            )

            MetricCard(
                title: "Cadence",
                value: cadenceText,
                unit: "RPM",
                isPrimary: false
            )

            MetricCard(
                title: "Distance",
                value: distanceText,
                unit: "km",
                isPrimary: false
            )

            MetricCard(
                title: "Time",
                value: elapsedText,
                unit: "mm:ss",
                isPrimary: false
            )
        }
    }
}

private struct TargetDistanceBar: View {
    let targetDistanceKm: Double?
    let canEdit: Bool
    let onUpdateTargetDistance: (Double?) -> Void

    @State private var showEditor = false

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("TARGET DISTANCE")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                Text(targetLabel)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
            }

            Spacer()

            Button {
                showEditor = true
            } label: {
                Text(targetDistanceKm == nil ? "Set Target" : "Edit")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(RideTheme.surface(RideTheme.accent, opacity: canEdit ? 0.2 : 0.12))
                    )
            }
            .disabled(!canEdit)

            if targetDistanceKm != nil {
                Button {
                    onUpdateTargetDistance(nil)
                } label: {
                    Text("Clear")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(RideTheme.surface(RideTheme.card, opacity: 0.8))
                        )
                }
                .disabled(!canEdit)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(RideTheme.card)
        )
        .sheet(isPresented: $showEditor) {
            TargetDistanceSheet(
                initialKm: targetDistanceKm,
                onSave: { value in
                    onUpdateTargetDistance(value)
                }
            )
        }
    }

    private var targetLabel: String {
        guard let targetDistanceKm, targetDistanceKm > 0 else { return "Off" }
        return String(format: "%.1f km auto-stop", targetDistanceKm)
    }
}

private struct TargetDistanceSheet: View {
    let initialKm: Double?
    let onSave: (Double) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Target Distance (km)") {
                    TextField("e.g. 10", text: $text)
                        .keyboardType(.decimalPad)
                }
                Section {
                    Text("The workout will stop automatically when this distance is reached.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Set Target")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let normalized = text.replacingOccurrences(of: ",", with: ".")
                        if let value = Double(normalized), value > 0 {
                            onSave(value)
                            dismiss()
                        }
                    }
                    .disabled(!isValidInput)
                }
            }
        }
        .onAppear {
            if let initialKm, initialKm > 0 {
                text = String(format: "%.1f", initialKm)
            }
        }
    }

    private var isValidInput: Bool {
        let normalized = text.replacingOccurrences(of: ",", with: ".")
        if let value = Double(normalized), value > 0 {
            return true
        }
        return false
    }
}

private struct MetricCard: View {
    let title: String
    let value: String
    let unit: String
    let isPrimary: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(value)
                    .font(.system(size: isPrimary ? 43 : 27, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.easeInOut(duration: 0.25), value: value)

                Text(unit)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 91, alignment: .leading)
        .padding(13)
        .background(
            RoundedRectangle(cornerRadius: 22)
                .fill(RideTheme.card.opacity(0.6))
                .shadow(color: Color.black.opacity(0.35), radius: 10, x: 0, y: 5)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }
}

private struct ControlRow: View {
    let isActive: Bool
    let isPaused: Bool
    let onStart: () -> Void
    let onPause: () -> Void
    let onStop: () -> Void

    var body: some View {
        HStack(spacing: 28) {
            CircularControlButton(
                systemName: "play.fill",
                color: Color.green,
                isEnabled: !isActive || isPaused,
                label: isPaused ? "Resume" : "Start",
                action: onStart
            )

            CircularControlButton(
                systemName: "pause.fill",
                color: Color.orange,
                isEnabled: isActive && !isPaused,
                label: "Pause",
                action: onPause
            )

            CircularControlButton(
                systemName: "stop.fill",
                color: Color.red,
                isEnabled: isActive,
                label: "Stop",
                action: onStop
            )
        }
        .padding(.vertical, 8)
    }
}

private struct CircularControlButton: View {
    let systemName: String
    let color: Color
    let isEnabled: Bool
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 64, height: 64)
                .background(
                    Circle()
                        .fill(color.opacity(isEnabled ? 0.9 : 0.25))
                        .shadow(color: color.opacity(0.4), radius: 12, x: 0, y: 6)
                )
        }
        .disabled(!isEnabled)
        .accessibilityLabel(label)
    }
}

private struct GraphSection: View {
    let speedSamples: [SpeedSample]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Speed")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)

            VStack(spacing: 12) {
                SpeedLineGraph(samples: speedSamples)
                    .frame(height: 120)

                SpeedHeatMap(samples: speedSamples)
                    .frame(height: 12)
            }
            .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(RideTheme.card)
        )
        }
    }
}

private struct SpeedLineGraph: View {
    let samples: [SpeedSample]

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let speeds = samples.map(\.speedKph)
            let maxSpeed = max(speeds.max() ?? 0, 1)

            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(RideTheme.track.opacity(0.6), lineWidth: 1)

                if samples.count >= 2 {
                    Path { path in
                        for (index, speed) in speeds.enumerated() {
                            let x = size.width * CGFloat(index) / CGFloat(max(speeds.count - 1, 1))
                            let y = size.height - (CGFloat(speed) / CGFloat(maxSpeed) * size.height)
                            if index == 0 {
                                path.move(to: CGPoint(x: x, y: y))
                            } else {
                                path.addLine(to: CGPoint(x: x, y: y))
                            }
                        }
                    }
                    .stroke(RideTheme.accent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    .animation(.easeInOut(duration: 0.35), value: speeds.count)
                } else {
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: size.height * 0.7))
                        path.addLine(to: CGPoint(x: size.width, y: size.height * 0.7))
                    }
                    .stroke(RideTheme.track, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                }
            }
        }
    }
}

private struct SpeedHeatMap: View {
    let samples: [SpeedSample]

    var body: some View {
        GeometryReader { _ in
            let blockCount = 24
            let speeds = samples.map(\.speedKph)
            let maxSpeed = max(speeds.max() ?? 0, 1)
            let values = heatValues(blockCount: blockCount, speeds: speeds)

            HStack(spacing: 4) {
                ForEach(0..<blockCount, id: \.self) { index in
                    Rectangle()
                        .fill(zoneColor(for: values[index], maxSpeed: maxSpeed))
                        .cornerRadius(3)
                        .animation(.easeInOut(duration: 0.35), value: values[index])
                }
            }
        }
    }

    private func heatValues(blockCount: Int, speeds: [Double]) -> [Double] {
        guard !speeds.isEmpty else { return Array(repeating: 0, count: blockCount) }
        let strideCount = max(speeds.count / blockCount, 1)
        return (0..<blockCount).map { index in
            let start = index * strideCount
            let end = min(start + strideCount, speeds.count)
            guard start < end else { return 0 }
            let slice = speeds[start..<end]
            let sum = slice.reduce(0, +)
            return sum / Double(slice.count)
        }
    }

    private func zoneColor(for speed: Double, maxSpeed: Double) -> Color {
        let normalized = maxSpeed > 0 ? speed / maxSpeed : 0
        switch normalized {
        case 0..<0.25:
            return RideTheme.accent.opacity(0.2)
        case 0.25..<0.5:
            return RideTheme.accent.opacity(0.4)
        case 0.5..<0.75:
            return RideTheme.accent.opacity(0.65)
        default:
            return RideTheme.accent
        }
    }
}

private struct BottomBar: View {
    let avgSpeedText: String
    let maxSpeedText: String
    let totalDistanceText: String

    var body: some View {
        ViewThatFits(in: .horizontal) {
            metricsRow(spacing: 20)
            metricsGrid
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(RideTheme.card)
        )
    }

    @ViewBuilder
    private func metricsRow(spacing: CGFloat) -> some View {
        HStack(spacing: spacing) {
            BottomMetric(title: "Avg Speed", value: avgSpeedText, unit: "km/h")
            BottomMetric(title: "Max Speed", value: maxSpeedText, unit: "km/h")
            BottomMetric(title: "Total Distance", value: totalDistanceText, unit: "km")
        }
    }

    private var metricsGrid: some View {
        let columns = [
            GridItem(.flexible(), spacing: 16),
            GridItem(.flexible(), spacing: 16)
        ]
        return LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
            BottomMetric(title: "Avg Speed", value: avgSpeedText, unit: "km/h")
            BottomMetric(title: "Max Speed", value: maxSpeedText, unit: "km/h")
            BottomMetric(title: "Total Distance", value: totalDistanceText, unit: "km")
        }
    }
}

private struct BottomMetric: View {
    let title: String
    let value: String
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(value)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.easeInOut(duration: 0.25), value: value)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Text(unit)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}


struct ProfileSelectionView: View {
    @ObservedObject var store: ProfileStore
    let selectionRequired: Bool

    @State private var showEditor = false
    @State private var editingProfile: Profile?
    @State private var deleteProfile: Profile?

    var body: some View {
        NavigationStack {
            Group {
                if store.profiles.isEmpty {
                    ContentUnavailableView(
                        "No profiles yet",
                        systemImage: "person.crop.circle",
                        description: Text("Create a profile to start tracking workouts.")
                    )
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(store.profiles) { profile in
                                Button {
                                    store.setActiveProfile(profile)
                                } label: {
                                    ProfileRow(
                                        profile: profile,
                                        isActive: profile.id == store.activeProfileId
                                    )
                                    .overlay(alignment: .trailing) {
                                        Menu {
                                            Button("Edit") {
                                                editingProfile = profile
                                            }
                                            Button("Delete", role: .destructive) {
                                                deleteProfile = profile
                                            }
                                        } label: {
                                            Image(systemName: "ellipsis.circle")
                                                .font(.system(size: 18, weight: .semibold))
                                                .foregroundStyle(.secondary)
                                                .padding(.trailing, 12)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                            }

                            Button {
                                editingProfile = nil
                                showEditor = true
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "plus.circle")
                                    Text("Add Profile")
                                }
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .foregroundStyle(RideTheme.accent)
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .background(
                                    RoundedRectangle(cornerRadius: 14)
                                        .stroke(RideTheme.accent.opacity(0.4), lineWidth: 1)
                                )
                            }
                            .padding(.top, 4)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                    }
                }
            }
            .navigationTitle("Profiles")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        editingProfile = nil
                        showEditor = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add Profile")
                }
            }
            .overlay(alignment: .top) {
                if selectionRequired && store.activeProfileId == nil {
                    Text("Select a profile to start a workout.")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .padding(.top, 12)
                        .allowsHitTesting(false)
                }
            }
        }
        .sheet(isPresented: $showEditor) {
            ProfileEditorSheet(
                title: "New Profile",
                initialName: "",
                onSave: { name in
                    store.addProfile(name: name)
                }
            )
        }
        .sheet(item: $editingProfile) { profile in
            ProfileEditorSheet(
                title: "Edit Profile",
                initialName: profile.name,
                onSave: { name in
                    store.updateProfile(id: profile.id, name: name)
                }
            )
        }
        .alert(
            "Delete Profile?",
            isPresented: Binding(
                get: { deleteProfile != nil },
                set: { if !$0 { deleteProfile = nil } }
            )
        ) {
            Button("Delete", role: .destructive) {
                if let deleteProfile {
                    store.deleteProfile(id: deleteProfile.id)
                }
                deleteProfile = nil
            }
            Button("Cancel", role: .cancel) {
                deleteProfile = nil
            }
        } message: {
            Text("This will remove all associated workouts from view. This action cannot be undone.")
        }
    }
}

private struct ProfileRow: View {
    let profile: Profile
    let isActive: Bool

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color(hex: profile.colorHex ?? RideTheme.accentHex))
                    .frame(width: 36, height: 36)
                Text(profile.initials)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
            }

            Text(profile.name)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)

            Spacer()

            if isActive {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(RideTheme.accent)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(isActive ? RideTheme.card.opacity(0.95) : RideTheme.card.opacity(0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(isActive ? RideTheme.accent.opacity(0.35) : Color.white.opacity(0.06), lineWidth: 1)
        )
    }
}

private struct ProfileEditorSheet: View {
    let title: String
    let initialName: String
    let onSave: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Profile Name") {
                    TextField("Name", text: $name)
                        .textInputAutocapitalization(.words)
                }
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(name)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .onAppear {
            name = initialName
        }
    }
}

private struct ProfileDropdown: View {
    let name: String
    let initials: String
    let colorHex: UInt32
    let activeProfileId: UUID
    let profiles: [Profile]
    let canChange: Bool
    let onSelect: (Profile) -> Void
    let onAdd: (String) -> Void

    @State private var showAddProfile = false

    var body: some View {
        Menu {
            ForEach(profiles) { profile in
                Button {
                    onSelect(profile)
                } label: {
                    if profile.id == activeProfileId {
                        Label(profile.name, systemImage: "checkmark")
                    } else {
                        Text(profile.name)
                    }
                }
            }
            Divider()
            Button {
                showAddProfile = true
            } label: {
                Label("Add Profile", systemImage: "plus")
            }
        } label: {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(Color(hex: colorHex))
                        .frame(width: 22, height: 22)
                    Text(initials)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                }

                Text(name)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)

                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(RideTheme.card)
            )
        }
        .disabled(!canChange)
        .opacity(canChange ? 1 : 0.5)
        .sheet(isPresented: $showAddProfile) {
            ProfileEditorSheet(
                title: "New Profile",
                initialName: "",
                onSave: { name in
                    onAdd(name)
                }
            )
        }
    }
}

private struct ConnectionIndicator: View {
    let isConnected: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "bicycle")
                .font(.system(size: 12, weight: .semibold))
            Circle()
                .fill(isConnected ? Color.green : Color.red)
                .frame(width: 6, height: 6)
        }
        .foregroundStyle(isConnected ? Color.green : Color.red)
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(
            Capsule()
                .fill(RideTheme.surface(isConnected ? Color.green : Color.red, opacity: isConnected ? 0.18 : 0.12))
        )
        .overlay(
            Capsule()
                .stroke(RideTheme.surface(isConnected ? Color.green : Color.red, opacity: 0.35), lineWidth: 1)
        )
        .opacity(isConnected ? 1 : 0.6)
        .accessibilityLabel(isConnected ? "Bike connected" : "Bike not connected")
    }
}

private struct ActiveProfileRow: View {
    let profile: Profile?

    var body: some View {
        HStack(spacing: 10) {
            if let profile {
                Circle()
                    .fill(Color(hex: profile.colorHex ?? RideTheme.accentHex))
                    .frame(width: 10, height: 10)
                Text(profile.name)
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Text("Active")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(RideTheme.accent)
            } else {
                Circle()
                    .fill(Color.gray.opacity(0.6))
                    .frame(width: 10, height: 10)
                Text("None selected")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private enum WorkoutState: String {
    case ready = "READY"
    case riding = "RIDING"
    case paused = "PAUSED"
}

private enum RideTheme {
    static let accentHex: UInt32 = 0xF06010
    static var surfaceOpacity: Double = 0
    static var background: Color { Color(hex: 0x0B0F14).opacity(surfaceOpacity) }
    static var backgroundSecondary: Color { Color(hex: 0x0E141C).opacity(surfaceOpacity) }
    static let accent = Color(hex: accentHex)
    static let track = Color.white.opacity(0.16)
    static var card: Color { Color(hex: 0x141A23).opacity(surfaceOpacity) }

    static func surface(_ color: Color, opacity: Double = 1) -> Color {
        color.opacity(opacity * surfaceOpacity)
    }
}

private struct ConnectionStatusRow: View {
    let isConnected: Bool

    var body: some View {
        HStack {
            Circle()
                .fill(isConnected ? Color.green : Color.orange)
                .frame(width: 8, height: 8)
            Text("Bike")
                .font(.system(size: 14, weight: .medium))
            Spacer()
            Text(isConnected ? "Connected" : "Not connected")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isConnected ? Color.green : Color.orange)
        }
    }
}

private struct CyclingBackground: View {
    var body: some View {
        Color.clear
        .ignoresSafeArea()
    }
}

private extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        let red = Double((hex >> 16) & 0xFF) / 255
        let green = Double((hex >> 8) & 0xFF) / 255
        let blue = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }
}
