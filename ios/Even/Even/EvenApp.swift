import SwiftUI

@main
struct EvenApp: App {
    var body: some Scene {
        WindowGroup {
            RouteCompareView()
                .tint(Color.brand)
        }
    }
}
