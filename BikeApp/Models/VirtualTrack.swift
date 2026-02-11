import Foundation

enum TrackSegmentType: String, CaseIterable, Hashable {
    case flat
    case sprint
    case climb
}

struct TrackSegment: Identifiable, Hashable {
    let id = UUID()
    let type: TrackSegmentType
    let lengthKm: Double
    let order: Int
}

struct TrackSegmentState: Hashable {
    let current: TrackSegment
    let next: TrackSegment?
    let segmentProgress: Double
    let distanceToNextKm: Double
    let distanceIntoSegmentKm: Double
}

struct VirtualTrack: Identifiable, Hashable {
    let id: UUID
    let name: String
    let distanceKm: Double
    let terrain: String
    let summary: String
    let elevationProfile: [Double]
    let accentHex: UInt32
    let segments: [TrackSegment]

    var distanceMeters: Double {
        distanceKm * 1000.0
    }

    func segmentState(for progressKm: Double) -> TrackSegmentState? {
        let sorted = segments.sorted { $0.order < $1.order }
        guard !sorted.isEmpty else { return nil }
        let clampedProgress = max(progressKm, 0)
        var cursor: Double = 0
        for (index, segment) in sorted.enumerated() {
            let end = cursor + max(segment.lengthKm, 0)
            if clampedProgress <= end || index == sorted.count - 1 {
                let distanceInto = max(min(clampedProgress - cursor, segment.lengthKm), 0)
                let progress = segment.lengthKm > 0 ? distanceInto / segment.lengthKm : 0
                let next = index + 1 < sorted.count ? sorted[index + 1] : nil
                let distanceToNext = max(end - clampedProgress, 0)
                return TrackSegmentState(
                    current: segment,
                    next: next,
                    segmentProgress: min(max(progress, 0), 1),
                    distanceToNextKm: distanceToNext,
                    distanceIntoSegmentKm: distanceInto
                )
            }
            cursor = end
        }
        return nil
    }
}

enum VirtualTrackCatalog {
    static let tracks: [VirtualTrack] = [
        VirtualTrack(
            id: UUID(uuidString: "B63F3C8D-1B85-4F44-9F90-7B2E6C3A5D01")!,
            name: "Sunrise Loop",
            distanceKm: 6.5,
            terrain: "Flat opener",
            summary: "Long straights with a smooth tempo.",
            elevationProfile: [0.1, 0.12, 0.1, 0.11, 0.13, 0.1, 0.12, 0.11, 0.1, 0.12, 0.1, 0.1],
            accentHex: 0xF5A524,
            segments: [
                TrackSegment(type: .flat, lengthKm: 2.0, order: 0),
                TrackSegment(type: .sprint, lengthKm: 1.0, order: 1),
                TrackSegment(type: .flat, lengthKm: 2.0, order: 2),
                TrackSegment(type: .climb, lengthKm: 1.5, order: 3)
            ]
        ),
        VirtualTrack(
            id: UUID(uuidString: "3A1C03E6-0C86-4A18-8D2E-3B8AA2E6C7F2")!,
            name: "River Run",
            distanceKm: 12.4,
            terrain: "Rolling",
            summary: "Gentle rollers that reward consistency.",
            elevationProfile: [0.2, 0.35, 0.3, 0.45, 0.25, 0.4, 0.3, 0.5, 0.35, 0.45, 0.3, 0.4],
            accentHex: 0x2BD0C8,
            segments: [
                TrackSegment(type: .flat, lengthKm: 2.0, order: 0),
                TrackSegment(type: .climb, lengthKm: 2.4, order: 1),
                TrackSegment(type: .flat, lengthKm: 3.0, order: 2),
                TrackSegment(type: .sprint, lengthKm: 1.5, order: 3),
                TrackSegment(type: .flat, lengthKm: 3.5, order: 4)
            ]
        ),
        VirtualTrack(
            id: UUID(uuidString: "7B6D9C44-5B2A-4D9E-8D6E-1356A5B1E9B3")!,
            name: "City Circuit",
            distanceKm: 10.0,
            terrain: "Intervals",
            summary: "Punchy blocks for speed changes.",
            elevationProfile: [0.2, 0.6, 0.3, 0.7, 0.25, 0.65, 0.3, 0.7, 0.2, 0.6, 0.25, 0.5],
            accentHex: 0x1F8EFA,
            segments: [
                TrackSegment(type: .sprint, lengthKm: 1.5, order: 0),
                TrackSegment(type: .flat, lengthKm: 2.0, order: 1),
                TrackSegment(type: .sprint, lengthKm: 1.5, order: 2),
                TrackSegment(type: .climb, lengthKm: 2.0, order: 3),
                TrackSegment(type: .flat, lengthKm: 3.0, order: 4)
            ]
        ),
        VirtualTrack(
            id: UUID(uuidString: "E2BCEB8D-1157-4F63-9A8E-9E2B4E124E77")!,
            name: "Forest Climb",
            distanceKm: 7.8,
            terrain: "Climb",
            summary: "A steady rise with a strong finish.",
            elevationProfile: [0.2, 0.25, 0.3, 0.4, 0.55, 0.7, 0.85, 0.95, 0.9, 0.8, 0.7, 0.6],
            accentHex: 0x31C48D,
            segments: [
                TrackSegment(type: .flat, lengthKm: 1.8, order: 0),
                TrackSegment(type: .climb, lengthKm: 2.0, order: 1),
                TrackSegment(type: .climb, lengthKm: 2.0, order: 2),
                TrackSegment(type: .sprint, lengthKm: 2.0, order: 3)
            ]
        ),
        VirtualTrack(
            id: UUID(uuidString: "9C6B0893-2B8C-4A25-8B2E-CA7F43CBEA41")!,
            name: "Alpine Pass",
            distanceKm: 18.0,
            terrain: "Long climb",
            summary: "Extended climb with a late push.",
            elevationProfile: [0.15, 0.2, 0.28, 0.35, 0.45, 0.55, 0.7, 0.82, 0.9, 0.95, 0.92, 0.88],
            accentHex: 0xD64550,
            segments: [
                TrackSegment(type: .flat, lengthKm: 3.0, order: 0),
                TrackSegment(type: .climb, lengthKm: 4.0, order: 1),
                TrackSegment(type: .climb, lengthKm: 4.0, order: 2),
                TrackSegment(type: .sprint, lengthKm: 3.0, order: 3),
                TrackSegment(type: .climb, lengthKm: 4.0, order: 4)
            ]
        )
    ]
}
