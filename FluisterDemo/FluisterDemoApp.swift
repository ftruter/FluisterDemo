import SwiftUI
import UIKit

final class FluisterAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        guard identifier == ModelDownloadRuntime.sessionIdentifier else {
            completionHandler()
            return
        }
        ModelDownloadRuntime.shared.backgroundCompletion = completionHandler
    }
}

@main
struct FluisterDemoApp: App {
    @UIApplicationDelegateAdaptor(FluisterAppDelegate.self) private var appDelegate
    @State private var transcriber = Transcriber()

    /// True when this process is hosting the test runner rather than the app.
    private static let isHostingTests =
        NSClassFromString("XCTestCase") != nil
        || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        || ProcessInfo.processInfo.environment["XCTestSessionIdentifier"] != nil

    var body: some Scene {
        WindowGroup {
            if Self.isHostingTests {
                // Keep the app pipeline dormant while hosting tests: RootView's
                // bootstrap loads a second multi-GB WhisperKit next to the test
                // suite's own instance (and the live UI can start a microphone
                // session), which gets the runner jetsam-killed on device.
                Text(verbatim: "Running tests")
            } else {
                RootView()
                    .environment(transcriber)
                    .environment(\.locale, transcriber.language.locale)
            }
        }
    }
}
