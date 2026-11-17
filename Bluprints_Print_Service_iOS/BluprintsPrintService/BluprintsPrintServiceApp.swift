import SwiftUI

@main
struct BluprintsPrintServiceApp: App {
    @StateObject private var ble = BLEPrinter()
    @StateObject private var inbox = JobInbox()
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            ContentView().environmentObject(ble).environmentObject(inbox)
                .onOpenURL { url in inbox.receive(url, busy: ble.busy) }
                .onChange(of: scenePhase) { phase in if phase == .background { ble.enteredBackground() } }
        }
    }
}
