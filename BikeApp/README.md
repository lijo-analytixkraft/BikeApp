# BikeApp (iPad)

SwiftUI iPad app for indoor cycling with FTMS cadence, software distance, and Apple Health workout export.

## Setup (Xcode)
1. Open Xcode and create a new **App** project.
   - Platform: iOS
   - Interface: SwiftUI
   - Language: Swift
   - Product name: BikeApp (or your choice)
2. Replace the generated files with the ones in this repo:
   - `BikeApp/BikeAppApp.swift`
   - `BikeApp/ContentView.swift`
3. Add the supporting files to the project (drag into Xcode, make sure they are included in the app target):
   - `BikeApp/Managers/BluetoothManager.swift`
   - `BikeApp/Managers/WorkoutSession.swift`
   - `BikeApp/Managers/HealthKitManager.swift`
   - `BikeApp/Utils/Data+LE.swift`
4. Add the Info.plist keys (or point the target to `BikeApp/Resources/Info.plist`):
   - `NSBluetoothAlwaysUsageDescription`
   - `NSHealthShareUsageDescription`
   - `NSHealthUpdateUsageDescription`
   - `UIDeviceFamily` = iPad only
5. Enable HealthKit capability:
   - Target > Signing & Capabilities > + Capability > **HealthKit**
   - Ensure the entitlements file includes `com.apple.developer.healthkit` (see `BikeApp/BikeApp.entitlements`).
6. Run on iPad. Bluetooth permission will be requested on first connect; Health permissions on first workout start.

## Distance model
Distance is derived from cadence with a configurable **meters per revolution** value. Adjust it in-app to match your bike.

## Notes
- Cadence parsing assumes FTMS Indoor Bike Data (2AD2) with flag `0x0008` (cadence only).
- Workout saves `HKWorkout` (cycling) and `distanceCycling` at the end of a session.
