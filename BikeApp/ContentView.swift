import Combine
import SwiftUI
import UIKit

struct ContentView: View {
    @StateObject private var bluetooth = BluetoothManager()
    @StateObject private var workout = WorkoutSession()
    @StateObject private var healthKit = HealthKitManager()
    @ObservedObject var profileStore: ProfileStore
    @ObservedObject var historyStore: WorkoutHistoryStore

    private let healthKitWritesEnabled = false

    @AppStorage("distanceUnit") private var distanceUnit: String = "km"
    @AppStorage("useTransparentUI") private var useTransparentUI: Bool = true

    @Environment(\.scenePhase) private var scenePhase
    @State private var showSetup = true
    @State private var selectedTrack: VirtualTrack?
    @State private var showTrackPicker = false

    var body: some View {
        ZStack {
            CyclingBackground()
            if showSetup || profileStore.activeProfile == nil {
                SetupView(
                    profiles: profileStore.profiles,
                    activeProfile: profileStore.activeProfile,
                    selectedTrack: selectedTrack,
                    targetDistanceKm: profileStore.activeProfile?.targetDistanceKm,
                    onSelectProfile: { profile in
                        profileStore.setActiveProfile(profile)
                    },
                    onAddProfile: { name in
                        profileStore.addProfile(name: name)
                    },
                    onUpdateTargetDistance: { targetKm in
                        if let activeProfile = profileStore.activeProfile {
                            profileStore.updateProfileTargetDistance(id: activeProfile.id, targetKm: targetKm)
                        }
                    },
                    onSelectTrack: { showTrackPicker = true },
                    onClearTrack: { selectedTrack = nil },
                    onStart: {
                        showSetup = false
                    }
                )
            } else if let activeProfile = profileStore.activeProfile {
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
                    },
                    selectedTrack: $selectedTrack,
                    onShowTrackPicker: { showTrackPicker = true },
                    onExitToSetup: {
                        showSetup = true
                    }
                )
            }
        }
        .sheet(isPresented: $showTrackPicker) {
            TrackPickerSheet(
                tracks: VirtualTrackCatalog.tracks,
                selectedTrackId: selectedTrack?.id,
                onSelect: { track in
                    selectedTrack = track
                }
            )
        }
        .onAppear {
            RideTheme.surfaceOpacity = useTransparentUI ? 0 : 1
            if !workout.isActive {
                showSetup = true
            }
        }
        .onChange(of: useTransparentUI) { _, newValue in
            RideTheme.surfaceOpacity = newValue ? 0 : 1
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                if !workout.isActive {
                    showSetup = true
                }
            }
        }
    }
}

private struct SetupView: View {
    let profiles: [Profile]
    let activeProfile: Profile?
    let selectedTrack: VirtualTrack?
    let targetDistanceKm: Double?
    let onSelectProfile: (Profile) -> Void
    let onAddProfile: (String) -> Void
    let onUpdateTargetDistance: (Double?) -> Void
    let onSelectTrack: () -> Void
    let onClearTrack: () -> Void
    let onStart: () -> Void

    @State private var showAddProfile = false

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let contentWidth = min(size.width * 0.92, 1100)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Ride Setup")
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        Text("Choose your profile and target before you ride. Track is optional.")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }

                    profileSection

                    VStack(alignment: .leading, spacing: 12) {
                        Text("TARGET")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                        TargetDistanceBar(
                            targetDistanceKm: targetDistanceKm,
                            canEdit: activeProfile != nil,
                            onUpdateTargetDistance: onUpdateTargetDistance
                        )
                        if activeProfile == nil {
                            Text("Select a profile to set a target distance.")
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("TRACK")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                        VirtualTrackCard(
                            track: selectedTrack,
                            speedKph: 0,
                            progressMeters: 0,
                            canEdit: true,
                            onSelect: onSelectTrack,
                            onClear: onClearTrack
                        )
                    }

                    HStack {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(startHint)
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            onStart()
                        } label: {
                            Text("Enter Workout")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 18)
                                .padding(.vertical, 10)
                                .background(
                                    Capsule()
                                        .fill(canStart ? RideTheme.accent : RideTheme.accent.opacity(0.3))
                                )
                        }
                        .disabled(!canStart)
                    }
                }
                .frame(maxWidth: contentWidth, alignment: .leading)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, max(24, size.width * 0.04))
                .padding(.vertical, max(24, size.height * 0.04))
            }
        }
        .sheet(isPresented: $showAddProfile) {
            ProfileEditorSheet(
                title: "New Profile",
                initialName: "",
                onSave: { name in
                    onAddProfile(name)
                }
            )
        }
    }

    private var profileSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("PROFILE")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    showAddProfile = true
                } label: {
                    Text("Add")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(RideTheme.surface(RideTheme.accent, opacity: 0.2))
                        )
                }
            }

            if profiles.isEmpty {
                Text("No profiles yet. Add one to begin.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 8) {
                    ForEach(profiles) { profile in
                        Button {
                            onSelectProfile(profile)
                        } label: {
                            ProfileRow(
                                profile: profile,
                                isActive: profile.id == activeProfile?.id
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var canStart: Bool {
        activeProfile != nil
    }

    private var startHint: String {
        if activeProfile == nil {
            return "Pick a profile to continue."
        }
        if selectedTrack == nil {
            return "No track selected. You can still start a workout."
        }
        return "All set. Enter the workout screen."
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
    @Binding var selectedTrack: VirtualTrack?
    let onShowTrackPicker: () -> Void
    let onExitToSetup: () -> Void

    @Environment(\.scenePhase) private var scenePhase
    @State private var saveInProgress = false
    @State private var actionMessage: String = ""
    @State private var workoutStartDistanceMeters: Double = 0
    @State private var autoStopTriggered = false
    @State private var trackStartDistanceMeters: Double = 0

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
                speedKph: workout.speedKph,
                cadenceText: cadenceText,
                distanceTitle: distanceMetricTitle,
                distanceText: distanceText,
                elapsedText: timeText,
                avgSpeedText: avgSpeedText,
                maxSpeedText: maxSpeedText,
                totalDistanceText: totalDistanceText,
                targetDistanceKm: targetDistanceKm,
                canEditTargetDistance: !workout.isActive,
                onUpdateTargetDistance: onUpdateTargetDistance,
                track: selectedTrack,
                    trackProgressMeters: trackProgressMeters,
                    canEditTrack: false,
                    onSelectTrack: onShowTrackPicker,
                    onClearTrack: clearTrackSelection,
                    canExitToSetup: !workout.isActive,
                    onExitToSetup: onExitToSetup,
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
        .onChange(of: selectedTrack?.id) { _, _ in
            trackStartDistanceMeters = workout.distanceMeters
            autoStopTriggered = false
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
        let riddenKm = workout.distanceMeters / 1000.0
        guard let targetDistanceKm, targetDistanceKm > 0 else {
            return String(format: "%.2f", riddenKm)
        }
        let remainingKm = max(targetDistanceKm - riddenKm, 0)
        return String(format: "%.2f", remainingKm)
    }

    private var distanceMetricTitle: String {
        guard let targetDistanceKm, targetDistanceKm > 0 else {
            return "Distance"
        }
        return "Remaining"
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

    private var trackProgressMeters: Double {
        guard selectedTrack != nil else { return 0 }
        return max(0, workout.distanceMeters - trackStartDistanceMeters)
    }

    private var autoStopDistanceKm: Double? {
        selectedTrack?.distanceKm ?? targetDistanceKm
    }

    private var autoStopBaselineMeters: Double {
        selectedTrack == nil ? workoutStartDistanceMeters : trackStartDistanceMeters
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
        if healthKitWritesEnabled {
            if healthKit.isAuthorized {
                beginWorkout()
            } else {
                healthKit.requestAuthorization { success in
                    if success {
                        beginWorkout()
                    } else {
                        actionMessage = "Health permission required to save workout"
                    }
                }
            }
        } else {
            beginWorkout()
        }
    }

    private func pauseWorkout() {
        workout.pause()
    }

    private func stopWorkout() {
        guard let summary = workout.stop() else { return }
        autoStopTriggered = false
        let trackProgress = selectedTrack.map { _ in
            max(0, summary.distanceMeters - trackStartDistanceMeters)
        }
        let trackCompleted = selectedTrack.map { track in
            guard let trackProgress else { return false }
            return trackProgress >= (track.distanceMeters - 0.5)
        }
        historyStore.add(
            summary: summary,
            profileId: activeProfileId,
            trackId: selectedTrack?.id,
            trackName: selectedTrack?.name,
            trackDistanceKm: selectedTrack?.distanceKm,
            trackProgressMeters: trackProgress,
            trackCompleted: trackCompleted
        )
        if healthKitWritesEnabled {
            saveInProgress = true
            let completionLabel = trackCompleted == true ? "Track complete" : "Workout complete"
            healthKit.saveWorkout(
                startDate: summary.startDate,
                endDate: summary.endDate,
                distanceMeters: summary.distanceMeters
            ) { success in
                saveInProgress = false
                actionMessage = success ? "\(completionLabel) saved" : "\(completionLabel) save failed"
            }
        } else {
            actionMessage = trackCompleted == true ? "Track complete (Health save disabled)" : "Workout complete (Health save disabled)"
        }
        onExitToSetup()
    }

    private func checkAutoStop(distanceMeters: Double) {
        guard workout.isActive, !autoStopTriggered else { return }
        guard let autoStopDistanceKm, autoStopDistanceKm > 0 else { return }
        let targetMeters = autoStopDistanceKm * 1000.0
        let traveledMeters = max(0, distanceMeters - autoStopBaselineMeters)
        if traveledMeters >= targetMeters {
            autoStopTriggered = true
            stopWorkout()
        }
    }

    private func beginWorkout() {
        workout.start()
        workoutStartDistanceMeters = workout.distanceMeters
        if selectedTrack != nil {
            trackStartDistanceMeters = workout.distanceMeters
        }
    }

    private func clearTrackSelection() {
        selectedTrack = nil
        autoStopTriggered = false
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
    let speedKph: Double
    let cadenceText: String
    let distanceTitle: String
    let distanceText: String
    let elapsedText: String
    let avgSpeedText: String
    let maxSpeedText: String
    let totalDistanceText: String
    let targetDistanceKm: Double?
    let canEditTargetDistance: Bool
    let onUpdateTargetDistance: (Double?) -> Void
    let track: VirtualTrack?
    let trackProgressMeters: Double
    let canEditTrack: Bool
    let onSelectTrack: () -> Void
    let onClearTrack: () -> Void
    let canExitToSetup: Bool
    let onExitToSetup: () -> Void
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
            let verticalSpacing: CGFloat = size.height < 880 ? 14 : 20
            let verticalPadding = max(16, size.height * 0.03)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: verticalSpacing) {
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
                        distanceTitle: distanceTitle,
                        distanceText: distanceText,
                        elapsedText: elapsedText
                    )

                    VirtualTrackCard(
                        track: track,
                        speedKph: speedKph,
                        progressMeters: trackProgressMeters,
                        canEdit: canEditTrack,
                        onSelect: onSelectTrack,
                        onClear: onClearTrack
                    )

                    ControlRow(
                        isActive: isActive,
                        isPaused: isPaused,
                        canExitToSetup: canExitToSetup,
                        onStart: onStart,
                        onPause: onPause,
                        onStop: onStop,
                        onExitToSetup: onExitToSetup
                    )

                    GraphSection(speedSamples: speedSamples)

                    BottomBar(
                        avgSpeedText: avgSpeedText,
                        maxSpeedText: maxSpeedText,
                        totalDistanceText: totalDistanceText
                    )
                }
                .frame(maxWidth: contentWidth)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, max(24, size.width * 0.04))
                .padding(.vertical, verticalPadding)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
    let distanceTitle: String
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
                title: distanceTitle,
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
    let canExitToSetup: Bool
    let onStart: () -> Void
    let onPause: () -> Void
    let onStop: () -> Void
    let onExitToSetup: () -> Void

    var body: some View {
        ZStack {
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
            .frame(maxWidth: .infinity, alignment: .center)

            HStack {
                Spacer(minLength: 0)
                if canExitToSetup {
                    Button {
                        onExitToSetup()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.backward.circle")
                                .font(.system(size: 17, weight: .semibold, design: .rounded))
                            Text("Exit")
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                        }
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(RideTheme.surface(RideTheme.card, opacity: 0.9))
                            )
                    }
                }
            }
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
            Text("Speed + Cadence")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)

            VStack(spacing: 12) {
                SpeedCadenceGraph(samples: speedSamples)
                    .frame(height: 140)

                CadenceLegendRow()
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(RideTheme.card)
            )
        }
    }
}

private struct SpeedCadenceGraph: View {
    let samples: [SpeedSample]

    var body: some View {
        GeometryReader { proxy in
            let chartSamples = tenSecondBuckets(from: samples)
            let speeds = chartSamples.map(\.speedKph)
            let cadences = chartSamples.map(\.cadenceRpm)
            let maxSpeed = max(speeds.max() ?? 0, 1)
            let maxCadence = max(cadences.max() ?? 0, 120)

            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(RideTheme.track.opacity(0.6), lineWidth: 1)

                if chartSamples.isEmpty {
                    Text("Waiting for ride data")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                } else {
                    Canvas { context, canvasSize in
                        let guideFractions: [CGFloat] = [0.2, 0.4, 0.6, 0.8]
                        for fraction in guideFractions {
                            let y = canvasSize.height * fraction
                            var guidePath = Path()
                            guidePath.move(to: CGPoint(x: 0, y: y))
                            guidePath.addLine(to: CGPoint(x: canvasSize.width, y: y))
                            context.stroke(
                                guidePath,
                                with: .color(Color.white.opacity(0.05)),
                                style: StrokeStyle(lineWidth: 1, lineCap: .round, dash: [3, 5])
                            )
                        }

                        let sampleCount = max(chartSamples.count, 1)
                        let slotWidth = canvasSize.width / CGFloat(sampleCount)
                        let barWidth = max(2, slotWidth * 0.68)
                        let sideWidth = max(1, barWidth * 0.2)

                        for index in chartSamples.indices {
                            let cadence = max(chartSamples[index].cadenceRpm, 0)
                            let zoneColor = Self.cadenceZoneColor(for: cadence)
                            let normalizedCadence = CGFloat(cadence / maxCadence)
                            let barHeight = max(2, normalizedCadence * canvasSize.height)
                            let x = CGFloat(index) * slotWidth + (slotWidth - barWidth) * 0.5
                            let rect = CGRect(
                                x: x,
                                y: canvasSize.height - barHeight,
                                width: barWidth,
                                height: barHeight
                            )

                            let barBody = Path(roundedRect: rect, cornerRadius: min(3, barWidth * 0.35))
                            context.fill(
                                barBody,
                                with: .linearGradient(
                                    Gradient(colors: [
                                        zoneColor.opacity(0.45),
                                        zoneColor.opacity(0.95)
                                    ]),
                                    startPoint: CGPoint(x: rect.midX, y: rect.minY),
                                    endPoint: CGPoint(x: rect.midX, y: rect.maxY)
                                )
                            )

                            let sideRect = CGRect(
                                x: rect.maxX - sideWidth,
                                y: rect.minY + 1,
                                width: sideWidth,
                                height: max(1, rect.height - 1)
                            )
                            context.fill(
                                Path(roundedRect: sideRect, cornerRadius: min(2, sideWidth)),
                                with: .color(Color.black.opacity(0.18))
                            )

                            let highlightRect = CGRect(
                                x: rect.minX + 1,
                                y: rect.minY + 1,
                                width: max(1, rect.width - sideWidth - 2),
                                height: min(6, max(2, rect.height * 0.14))
                            )
                            context.fill(
                                Path(roundedRect: highlightRect, cornerRadius: min(2, highlightRect.height * 0.5)),
                                with: .color(Color.white.opacity(0.22))
                            )
                        }

                        if chartSamples.count >= 2 {
                            for index in 1..<chartSamples.count {
                                let previous = chartSamples[index - 1]
                                let current = chartSamples[index]

                                let x0 = canvasSize.width * CGFloat(index - 1) / CGFloat(chartSamples.count - 1)
                                let y0 = canvasSize.height - (CGFloat(previous.speedKph) / CGFloat(maxSpeed) * canvasSize.height)
                                let x1 = canvasSize.width * CGFloat(index) / CGFloat(chartSamples.count - 1)
                                let y1 = canvasSize.height - (CGFloat(current.speedKph) / CGFloat(maxSpeed) * canvasSize.height)

                                var segment = Path()
                                segment.move(to: CGPoint(x: x0, y: y0))
                                segment.addLine(to: CGPoint(x: x1, y: y1))

                                context.stroke(
                                    segment,
                                    with: .color(Color.black.opacity(0.3)),
                                    style: StrokeStyle(lineWidth: 4.0, lineCap: .round, lineJoin: .round)
                                )

                                context.stroke(
                                    segment,
                                    with: .color(Self.cadenceZoneColor(for: max(current.cadenceRpm, 0))),
                                    style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
                                )
                            }
                        }
                    }
                    .animation(.easeInOut(duration: 0.25), value: chartSamples.count)
                }
            }
        }
    }

    private func tenSecondBuckets(from samples: [SpeedSample]) -> [SpeedSample] {
        guard !samples.isEmpty else { return [] }
        let bucketInterval: TimeInterval = 10
        var buckets: [SpeedSample] = []

        var currentBucketStart = floor(samples[0].timestamp.timeIntervalSinceReferenceDate / bucketInterval) * bucketInterval
        var speedSum = 0.0
        var cadenceSum = 0.0
        var sampleCount = 0

        func flushBucket() {
            guard sampleCount > 0 else { return }
            let bucketTimestamp = Date(timeIntervalSinceReferenceDate: currentBucketStart + (bucketInterval / 2))
            buckets.append(
                SpeedSample(
                    timestamp: bucketTimestamp,
                    speedKph: speedSum / Double(sampleCount),
                    cadenceRpm: cadenceSum / Double(sampleCount)
                )
            )
        }

        for sample in samples {
            let bucketStart = floor(sample.timestamp.timeIntervalSinceReferenceDate / bucketInterval) * bucketInterval
            if bucketStart != currentBucketStart {
                flushBucket()
                currentBucketStart = bucketStart
                speedSum = 0
                cadenceSum = 0
                sampleCount = 0
            }
            speedSum += sample.speedKph
            cadenceSum += sample.cadenceRpm
            sampleCount += 1
        }

        flushBucket()
        return buckets
    }

    private static func cadenceZoneColor(for cadence: Double) -> Color {
        if cadence > 110 {
            return .red
        }
        if cadence < 30 {
            return .white
        }
        if cadence < 50 {
            return .blue
        }
        if cadence < 70 {
            return .yellow
        }
        return .green
    }
}

private struct CadenceLegendRow: View {
    var body: some View {
        HStack(spacing: 10) {
            legendItem(color: .white, label: "< 30")
            legendItem(color: .blue, label: "30-50")
            legendItem(color: .yellow, label: "50-70")
            legendItem(color: .green, label: "70-110")
            legendItem(color: .red, label: "> 110")
            Spacer(minLength: 0)
            Text("Bars are 10s cadence buckets")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color.opacity(0.9))
                .frame(width: 8, height: 8)
            Text(label)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
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
                VStack(spacing: 6) {
                    if selectionRequired && store.activeProfileId == nil {
                        Text("Select a profile to start a workout.")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 12)
                .allowsHitTesting(false)
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

enum RideTheme {
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

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        let red = Double((hex >> 16) & 0xFF) / 255
        let green = Double((hex >> 8) & 0xFF) / 255
        let blue = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }
}
