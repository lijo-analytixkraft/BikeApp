import SwiftUI

@main
struct BikeAppApp: App {
    @StateObject private var profileStore: ProfileStore
    @StateObject private var historyStore: WorkoutHistoryStore

    init() {
        let profileStore = ProfileStore()
        let historyStore = WorkoutHistoryStore()
        _profileStore = StateObject(wrappedValue: profileStore)
        _historyStore = StateObject(wrappedValue: historyStore)
    }

    var body: some Scene {
        WindowGroup {
            RootView(profileStore: profileStore, historyStore: historyStore)
        }
    }
}

private struct RootView: View {
    @ObservedObject var profileStore: ProfileStore
    @ObservedObject var historyStore: WorkoutHistoryStore

    var body: some View {
        if profileStore.activeProfileId == nil {
            ProfileSelectionView(store: profileStore, selectionRequired: true)
        } else {
            ContentView(profileStore: profileStore, historyStore: historyStore)
        }
    }
}
