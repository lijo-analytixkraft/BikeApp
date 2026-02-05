import Foundation
import Combine
import HealthKit

final class HealthKitManager: ObservableObject {
    @Published private(set) var isAuthorized: Bool = false
    @Published private(set) var lastErrorMessage: String?
    @Published private(set) var lastSaveMessage: String?

    private let healthStore = HKHealthStore()

    func requestAuthorization(completion: ((Bool) -> Void)? = nil) {
        guard HKHealthStore.isHealthDataAvailable() else {
            setError("Health data unavailable on this device")
            completion?(false)
            return
        }

        let workoutType = HKObjectType.workoutType()
        guard let distanceType = HKObjectType.quantityType(forIdentifier: .distanceCycling) else {
            setError("Distance cycling type unavailable")
            completion?(false)
            return
        }

        let shareTypes: Set<HKSampleType> = [workoutType, distanceType]
        let readTypes: Set<HKObjectType> = [workoutType, distanceType]

        healthStore.requestAuthorization(toShare: shareTypes, read: readTypes) { [weak self] success, error in
            DispatchQueue.main.async {
                if let error {
                    self?.setError(error.localizedDescription)
                    completion?(false)
                    return
                }
                self?.isAuthorized = success
                if success {
                    self?.lastSaveMessage = "Health access granted"
                }
                completion?(success)
            }
        }
    }

    func saveWorkout(startDate: Date, endDate: Date, distanceMeters: Double, completion: ((Bool) -> Void)? = nil) {
        guard HKHealthStore.isHealthDataAvailable() else {
            setError("Health data unavailable")
            completion?(false)
            return
        }

        guard let distanceType = HKObjectType.quantityType(forIdentifier: .distanceCycling) else {
            setError("Distance cycling type unavailable")
            completion?(false)
            return
        }

        let distanceQuantity = HKQuantity(unit: .meter(), doubleValue: distanceMeters)
        if #available(iOS 17.0, *) {
            let configuration = HKWorkoutConfiguration()
            configuration.activityType = .cycling
            configuration.locationType = .unknown
            let builder = HKWorkoutBuilder(healthStore: healthStore, configuration: configuration, device: .local())

            builder.beginCollection(withStart: startDate) { [weak self] success, error in
                if let error {
                    self?.setError(error.localizedDescription)
                    completion?(false)
                    return
                }
                if !success {
                    self?.setError("Failed to begin workout collection")
                    completion?(false)
                    return
                }
                let distanceSample = HKQuantitySample(
                    type: distanceType,
                    quantity: distanceQuantity,
                    start: startDate,
                    end: endDate
                )
                builder.add([distanceSample]) { success, error in
                    if let error {
                        self?.setError(error.localizedDescription)
                        completion?(false)
                        return
                    }
                    if !success {
                        self?.setError("Failed to add workout samples")
                        completion?(false)
                        return
                    }
                    builder.endCollection(withEnd: endDate) { success, error in
                        if let error {
                            self?.setError(error.localizedDescription)
                            completion?(false)
                            return
                        }
                        if !success {
                            self?.setError("Failed to end workout collection")
                            completion?(false)
                            return
                        }
                        builder.finishWorkout { [weak self] _, error in
                            DispatchQueue.main.async {
                                if let error {
                                    self?.setError(error.localizedDescription)
                                    completion?(false)
                                } else {
                                    self?.lastSaveMessage = "Workout saved to Apple Fitness"
                                    completion?(true)
                                }
                            }
                        }
                    }
                }
            }
        } else {
            let workout = HKWorkout(
                activityType: .cycling,
                start: startDate,
                end: endDate,
                duration: endDate.timeIntervalSince(startDate),
                totalEnergyBurned: nil,
                totalDistance: distanceQuantity,
                metadata: [HKMetadataKeyWasUserEntered: true]
            )

            healthStore.save(workout) { [weak self] success, error in
                if let error {
                    self?.setError(error.localizedDescription)
                    completion?(false)
                    return
                }
                let distanceSample = HKQuantitySample(
                    type: distanceType,
                    quantity: distanceQuantity,
                    start: startDate,
                    end: endDate
                )
                self?.healthStore.save(distanceSample) { sampleSaved, sampleError in
                    DispatchQueue.main.async {
                        if let sampleError {
                            self?.setError(sampleError.localizedDescription)
                            completion?(false)
                            return
                        }
                        if success && sampleSaved {
                            self?.lastSaveMessage = "Workout saved to Apple Fitness"
                            completion?(true)
                        } else {
                            self?.setError("Failed to save workout")
                            completion?(false)
                        }
                    }
                }
            }
        }
    }

    private func setError(_ message: String) {
        DispatchQueue.main.async {
            self.lastErrorMessage = message
        }
    }
}
