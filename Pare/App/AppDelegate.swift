// AppDelegate.swift - Application Lifecycle & Background Scheduler Integration
#if canImport(UIKit)
import UIKit

public final class AppDelegate: NSObject, UIApplicationDelegate {
    public func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Register the background deep clean task with the iOS kernel scheduler
        PareDeepCleanTask.shared.register()
        PareDeepCleanTask.shared.scheduleNext()
        return true
    }
}
#endif
