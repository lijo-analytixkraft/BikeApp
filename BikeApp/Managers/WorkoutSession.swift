import Combine
import Foundation

struct WorkoutSummary {
    let startDate: Date
    let endDate: Date
    let distanceMeters: Double
    let elapsedSeconds: TimeInterval
}

struct SpeedSample: Identifiable {
    let id = UUID()
    let timestamp: Date
    let speedKph: Double
    let cadenceRpm: Double
}

struct PerformanceStats {
    let averageSpeedKph: Double
    let distanceMeters: Double
    let duration: TimeInterval
}

final class WorkoutSession: ObservableObject {
    @Published private(set) var cadenceRpm: Double = 0
    @Published private(set) var speedKph: Double = 0
    @Published private(set) var distanceMeters: Double = 0
    @Published private(set) var elapsedSeconds: TimeInterval = 0
    @Published private(set) var isActive: Bool = false
    @Published private(set) var isPaused: Bool = false
    @Published private(set) var speedSamples: [SpeedSample] = []

    var metersPerRevolution: Double = 2.1

    private var timer: Timer?
    private var lastTickDate: Date?
    private(set) var startDate: Date?
    private(set) var endDate: Date?
    var lastTenMinuteStats: PerformanceStats {
        guard speedSamples.count >= 2 else {
            return PerformanceStats(averageSpeedKph: 0, distanceMeters: 0, duration: 0)
        }

        var distanceMeters: Double = 0
        for index in 1..<speedSamples.count {
            let previous = speedSamples[index - 1]
            let current = speedSamples[index]
            let delta = current.timestamp.timeIntervalSince(previous.timestamp)
            let avgKph = (previous.speedKph + current.speedKph) / 2.0
            distanceMeters += (avgKph / 3.6) * delta
        }

        let duration = speedSamples.last!.timestamp.timeIntervalSince(speedSamples.first!.timestamp)
        guard duration > 0 else {
            return PerformanceStats(averageSpeedKph: 0, distanceMeters: 0, duration: 0)
        }
        let averageSpeedKph = (distanceMeters / duration) * 3.6
        return PerformanceStats(averageSpeedKph: averageSpeedKph, distanceMeters: distanceMeters, duration: duration)
    }

    func start() {
        guard !isActive else { return }
        cadenceRpm = 0
        speedKph = 0
        distanceMeters = 0
        elapsedSeconds = 0
        speedSamples = []
        isActive = true
        isPaused = false
        startDate = Date()
        endDate = nil
        lastTickDate = startDate
        startTimer()
    }

    func stop() -> WorkoutSummary? {
        guard isActive, let startDate else { return nil }
        isActive = false
        isPaused = false
        timer?.invalidate()
        timer = nil
        let end = Date()
        endDate = end
        lastTickDate = nil
        let summary = WorkoutSummary(
            startDate: startDate,
            endDate: end,
            distanceMeters: distanceMeters,
            elapsedSeconds: elapsedSeconds
        )
        return summary
    }

    func pause() {
        guard isActive, !isPaused else { return }
        isPaused = true
        timer?.invalidate()
        timer = nil
        lastTickDate = nil
    }

    func resume() {
        guard isActive, isPaused else { return }
        isPaused = false
        lastTickDate = Date()
        startTimer()
    }

    func reset() {
        guard !isActive else { return }
        cadenceRpm = 0
        speedKph = 0
        distanceMeters = 0
        elapsedSeconds = 0
        isPaused = false
        startDate = nil
        endDate = nil
        lastTickDate = nil
        speedSamples = []
    }

    func updateMetrics(cadenceRpm: Double, speedKph: Double?) {
        self.cadenceRpm = cadenceRpm
        if let speedKph {
            self.speedKph = speedKph
        } else {
            let metersPerMinute = cadenceRpm * metersPerRevolution
            self.speedKph = metersPerMinute * 60.0 / 1000.0
        }
    }

    private func tick() {
        guard isActive, !isPaused else { return }
        let now = Date()
        if let lastTickDate {
            let delta = now.timeIntervalSince(lastTickDate)
            elapsedSeconds += delta
            let metersPerSecond = max(speedKph, 0) / 3.6
            distanceMeters += metersPerSecond * delta
        }
        lastTickDate = now
        recordSpeedSample(at: now)
    }

    private func startTimer() {
        let newTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        timer = newTimer
        RunLoop.main.add(newTimer, forMode: .common)
    }

    func syncAfterAppBecameActive() {
        guard isActive, !isPaused else { return }
        let now = Date()
        if let lastTickDate {
            let delta = now.timeIntervalSince(lastTickDate)
            if delta > 1 {
                elapsedSeconds += delta
                let metersPerSecond = max(speedKph, 0) / 3.6
                distanceMeters += metersPerSecond * delta
            }
        }
        lastTickDate = now
        recordSpeedSample(at: now)
    }

    private func recordSpeedSample(at timestamp: Date) {
        speedSamples.append(
            SpeedSample(
                timestamp: timestamp,
                speedKph: speedKph,
                cadenceRpm: cadenceRpm
            )
        )
    }
}
