import Foundation
import SwiftUI

struct VirtualTrackCard: View {
    let track: VirtualTrack?
    let speedKph: Double
    let progressMeters: Double
    let canEdit: Bool
    let onSelect: () -> Void
    let onClear: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Text("VIRTUAL TRACK")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)

                Spacer()

                if canEdit {
                    Button {
                        onSelect()
                    } label: {
                        Text(track == nil ? "Choose Track" : "Change")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(RideTheme.surface(RideTheme.accent, opacity: 0.22))
                            )
                    }

                    if track != nil {
                        Button {
                            onClear()
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
                    }
                }
            }

            if let track {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(track.name)
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)

                        Text("\(track.terrain) - \(formattedDistance(track.distanceKm))")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)

                        Text(track.summary)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    TrackProfilePreview(
                        points: track.elevationProfile,
                        color: Color(hex: track.accentHex)
                    )
                    .frame(width: 120, height: 42)
                    .padding(.top, 4)
                }

                TrackProgressBar(
                    progress: progressFraction(for: track),
                    accent: Color(hex: track.accentHex)
                )
                .frame(height: 10)

                if let segmentState = track.segmentState(for: progressMeters / 1000.0) {
                    TrackLaneView(
                        segmentType: segmentState.current.type,
                        speedKph: speedKph,
                        segmentProgress: segmentState.segmentProgress,
                        upcoming: upcomingPreview(from: segmentState),
                        pulseTrigger: pulseTriggerKey(segmentState: segmentState)
                    )
                    .frame(height: 58)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.white.opacity(0.05), lineWidth: 1)
                    )
                }

                HStack {
                    Text("\(formattedDistance(progressMeters / 1000.0)) / \(formattedDistance(track.distanceKm))")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                    Spacer()
                    Text(remainingText(for: track))
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                Text("Auto-finish at \(formattedDistance(track.distanceKm)). Track overrides profile target.")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)

                if !canEdit {
                    Text("Track locked while ride is active.")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            } else {
                Text(canEdit
                    ? "Select a track to auto-finish and log it in your history."
                    : "No track selected for this workout."
                )
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(RideTheme.card)
        )
    }

    private func formattedDistance(_ km: Double) -> String {
        String(format: "%.1f km", km)
    }

    private func progressFraction(for track: VirtualTrack) -> Double {
        guard track.distanceMeters > 0 else { return 0 }
        return min(max(progressMeters / track.distanceMeters, 0), 1)
    }

    private func remainingText(for track: VirtualTrack) -> String {
        let remainingKm = max(track.distanceKm - (progressMeters / 1000.0), 0)
        return "\(formattedDistance(remainingKm)) remaining"
    }

    private func upcomingPreview(from state: TrackSegmentState) -> TrackLaneUpcoming? {
        guard let next = state.next, state.distanceToNextKm > 0 else { return nil }
        let fadeDistance = min(max(state.distanceToNextKm, 0), 0.6)
        let opacity = min(max(1 - (fadeDistance / 0.6), 0), 1)
        return TrackLaneUpcoming(
            label: "Next: \(segmentLabel(next.type)) - \(String(format: "%.1f km", state.distanceToNextKm))",
            color: segmentColor(next.type),
            opacity: opacity
        )
    }

    private func segmentLabel(_ type: TrackSegmentType) -> String {
        switch type {
        case .flat:
            return "Flat"
        case .sprint:
            return "Sprint"
        case .climb:
            return "Climb"
        }
    }

    private func segmentColor(_ type: TrackSegmentType) -> Color {
        switch type {
        case .flat:
            return Color.white.opacity(0.7)
        case .sprint:
            return RideTheme.accent
        case .climb:
            return Color(hex: 0xD49A5A)
        }
    }

    private func pulseTriggerKey(segmentState: TrackSegmentState) -> Int {
        let kmMarker = Int((progressMeters / 1000.0).rounded(.down))
        return kmMarker * 100 + segmentState.current.order
    }

}

struct TrackLaneUpcoming: Hashable {
    let label: String
    let color: Color
    let opacity: Double
}

struct TrackLaneView: View {
    let segmentType: TrackSegmentType
    let speedKph: Double
    let segmentProgress: Double
    let upcoming: TrackLaneUpcoming?
    let pulseTrigger: Int

    @State private var pulse = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            laneBackground
                .overlay(markerFlow)
                .overlay(pulseOverlay)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.white.opacity(0.04), lineWidth: 1)
                )

            if let upcoming {
                Text(upcoming.label)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(upcoming.color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(RideTheme.surface(upcoming.color, opacity: 0.18))
                    )
                    .opacity(upcoming.opacity)
                    .padding(.leading, 10)
                    .padding(.top, -20)
            }
        }
        .rotationEffect(.degrees(segmentType == .climb ? -2.5 : 0))
        .offset(y: segmentType == .climb ? -4 : 0)
        .onChange(of: pulseTrigger) { _, _ in
            triggerPulse()
        }
    }

    private var laneBackground: some View {
        RoundedRectangle(cornerRadius: 14)
            .fill(laneGradient)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(laneEdgeColor, lineWidth: 1)
            )
    }

    private var laneGradient: LinearGradient {
        let base = laneBaseColor
        return LinearGradient(
            colors: [
                base.opacity(0.8),
                base.opacity(0.55),
                base.opacity(0.85)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private var laneBaseColor: Color {
        switch segmentType {
        case .flat:
            return RideTheme.card
        case .sprint:
            return RideTheme.accent.opacity(0.45)
        case .climb:
            return Color(hex: 0x2B2018)
        }
    }

    private var laneEdgeColor: Color {
        switch segmentType {
        case .flat:
            return Color.white.opacity(0.08)
        case .sprint:
            return RideTheme.accent.opacity(0.35)
        case .climb:
            return Color(hex: 0xD49A5A).opacity(0.2)
        }
    }

    private var markerFlow: some View {
        TimelineView(.animation) { context in
            GeometryReader { proxy in
                let size = proxy.size
                let dash = dashStyle
                let dashCount = Int(size.width / dash.spacing) + 3
                let offset = markerOffset(time: context.date.timeIntervalSinceReferenceDate, spacing: dash.spacing)
                let baseY = size.height * 0.5
                let verticalShift = segmentType == .climb ? -size.height * 0.12 : 0

                ZStack {
                    ForEach(0..<dashCount, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(dash.color)
                            .frame(width: dash.length, height: dash.thickness)
                            .shadow(color: dash.glowColor, radius: dash.glowRadius, x: 0, y: 0)
                            .position(
                                x: size.width - (CGFloat(index) * dash.spacing + offset),
                                y: baseY + verticalShift
                            )
                            .opacity(dash.opacity)
                    }

                    if segmentType == .sprint {
                        SprintStreaksView(progress: segmentProgress)
                            .frame(width: size.width, height: size.height)
                    }
                }
            }
        }
    }

    private var dashStyle: DashStyle {
        let baseOpacity: Double
        switch segmentType {
        case .flat:
            baseOpacity = 0.6
        case .sprint:
            baseOpacity = 0.85
        case .climb:
            baseOpacity = 0.45
        }

        return DashStyle(
            length: segmentType == .sprint ? 16 : 20,
            thickness: segmentType == .climb ? 5 : 4,
            spacing: segmentType == .sprint ? 26 : 34,
            opacity: baseOpacity,
            color: segmentType == .climb ? Color(hex: 0xB8834A) : Color.white,
            glowColor: segmentType == .sprint ? RideTheme.accent.opacity(0.6) : Color.clear,
            glowRadius: segmentType == .sprint ? 6 : 0
        )
    }

    private func markerOffset(time: TimeInterval, spacing: CGFloat) -> CGFloat {
        let speedFactor: Double
        switch segmentType {
        case .flat:
            speedFactor = 1.0
        case .sprint:
            speedFactor = 1.25
        case .climb:
            speedFactor = 0.7
        }
        let normalizedSpeed = max(speedKph, 0)
        let pixelsPerSecond = (normalizedSpeed / 30.0) * 110.0 * speedFactor
        let rawOffset = (time * pixelsPerSecond).truncatingRemainder(dividingBy: Double(spacing))
        return CGFloat(rawOffset)
    }

    private var pulseOverlay: some View {
        RoundedRectangle(cornerRadius: 14)
            .stroke(Color.white.opacity(pulse ? 0.45 : 0), lineWidth: pulse ? 2 : 0)
            .shadow(color: Color.white.opacity(pulse ? 0.35 : 0), radius: pulse ? 10 : 0)
            .animation(.easeOut(duration: 0.3), value: pulse)
    }

    private func triggerPulse() {
        withAnimation(.easeOut(duration: 0.2)) {
            pulse = true
        }
        withAnimation(.easeIn(duration: 0.6).delay(0.15)) {
            pulse = false
        }
#if canImport(UIKit)
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        generator.impactOccurred()
#endif
    }
}

private struct DashStyle {
    let length: CGFloat
    let thickness: CGFloat
    let spacing: CGFloat
    let opacity: Double
    let color: Color
    let glowColor: Color
    let glowRadius: CGFloat
}

private struct SprintStreaksView: View {
    let progress: Double

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let streakCount = 6
            let baseOpacity = 0.15 + (progress * 0.2)
            ZStack {
                ForEach(0..<streakCount, id: \.self) { index in
                    Capsule()
                        .fill(RideTheme.accent.opacity(baseOpacity))
                        .frame(width: size.width * 0.22, height: 3)
                        .offset(x: CGFloat(index) * size.width * 0.12, y: CGFloat(index % 2 == 0 ? -10 : 12))
                        .blur(radius: 2)
                }
            }
        }
        .blendMode(.screen)
    }
}

struct TrackPickerSheet: View {
    let tracks: [VirtualTrack]
    let selectedTrackId: UUID?
    let onSelect: (VirtualTrack) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 14) {
                    ForEach(tracks) { track in
                        Button {
                            onSelect(track)
                            dismiss()
                        } label: {
                            TrackPickerCard(
                                track: track,
                                isSelected: track.id == selectedTrackId
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(20)
            }
            .navigationTitle("Choose Track")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct TrackPickerCard: View {
    let track: VirtualTrack
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text(track.name)
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("\(track.terrain) - \(String(format: "%.1f km", track.distanceKm))")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if isSelected {
                    Text("Selected")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(RideTheme.accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(RideTheme.surface(RideTheme.accent, opacity: 0.2))
                        )
                }
            }

            TrackProfilePreview(points: track.elevationProfile, color: Color(hex: track.accentHex))
                .frame(height: 50)

            Text(track.summary)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(RideTheme.card)
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(
                            isSelected ? Color(hex: track.accentHex).opacity(0.6) : Color.white.opacity(0.08),
                            lineWidth: 1
                        )
                )
        )
    }
}

private struct TrackProfilePreview: View {
    let points: [Double]
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let normalized = normalizedPoints(points)

            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(RideTheme.surface(RideTheme.card, opacity: 0.9))

                if normalized.count > 1 {
                    Path { path in
                        for (index, value) in normalized.enumerated() {
                            let x = size.width * CGFloat(index) / CGFloat(max(normalized.count - 1, 1))
                            let y = size.height - (CGFloat(value) * size.height)
                            if index == 0 {
                                path.move(to: CGPoint(x: x, y: y))
                            } else {
                                path.addLine(to: CGPoint(x: x, y: y))
                            }
                        }
                    }
                    .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                    Path { path in
                        let baseY = size.height
                        path.move(to: CGPoint(x: 0, y: baseY))
                        for (index, value) in normalized.enumerated() {
                            let x = size.width * CGFloat(index) / CGFloat(max(normalized.count - 1, 1))
                            let y = size.height - (CGFloat(value) * size.height)
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                        path.addLine(to: CGPoint(x: size.width, y: baseY))
                        path.closeSubpath()
                    }
                    .fill(color.opacity(0.15))
                }
            }
        }
    }

    private func normalizedPoints(_ points: [Double]) -> [Double] {
        guard let minValue = points.min(), let maxValue = points.max() else { return [] }
        let range = max(maxValue - minValue, 0.01)
        return points.map { ($0 - minValue) / range }
    }
}

private struct TrackProgressBar: View {
    let progress: Double
    let accent: Color

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let clamped = min(max(progress, 0), 1)
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(RideTheme.track.opacity(0.7))
                RoundedRectangle(cornerRadius: 6)
                    .fill(accent)
                    .frame(width: width * CGFloat(clamped))
                    .animation(.easeInOut(duration: 0.25), value: clamped)
            }
        }
    }
}
