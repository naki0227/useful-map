import Presentation
import SwiftUI

@main
struct UsefulMapApp: App {
    private let dependencies = CompositionRoot.makeDependencies()

    var body: some Scene {
        WindowGroup {
            RootView(dependencies: dependencies)
        }
    }
}
