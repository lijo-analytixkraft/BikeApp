# BikeApp (iPad)

SwiftUI iPad app for indoor cycling with FTMS cadence and local profile/workout storage.

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
   - `BikeApp/Utils/Data+LE.swift`
4. Add the Info.plist keys (or point the target to `BikeApp/Resources/Info.plist`):
   - `NSBluetoothAlwaysUsageDescription`
   - `UIDeviceFamily` = iPad only
5. Run on iPad. Bluetooth permission will be requested on first connect.

## Distance model
Distance is derived from cadence with a configurable **meters per revolution** value. Adjust it in-app to match your bike.

## Notes
- Cadence parsing assumes FTMS Indoor Bike Data (2AD2) with flag `0x0008` (cadence only).
