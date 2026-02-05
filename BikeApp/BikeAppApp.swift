import SwiftUI

@main
struct BikeAppApp: App {
    @StateObject private var profileStore: ProfileStore

    init() {
        _profileStore = StateObject(wrappedValue: ProfileStore())
    }

    var body: some Scene {
        WindowGroup {
            RootView(profileStore: profileStore)
        }
    }
}

private struct RootView: View {
    @ObservedObject var profileStore: ProfileStore

    var body: some View {
        if profileStore.activeProfileId == nil {
            ProfileSelectionView(store: profileStore, selectionRequired: true)
        } else {
            ContentView(profileStore: profileStore)
        }
    }
}
