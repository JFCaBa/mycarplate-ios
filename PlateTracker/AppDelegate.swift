//
//  AppDelegate.swift
//  PlateTracker
//
//  Created by Jose on 21/07/2025.
//

import UIKit
import SDWebImage
import SDWebImageSVGCoder

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        SDImageCodersManager.shared.addCoder(SDImageSVGCoder.shared)
        // Eagerly create the URLSession.background instance so its delegate
        // is live before iOS delivers any pending events on a relaunch.
        BackgroundVehicleFetcher.shared.bootstrap()
        return true
    }

    /// Called when iOS relaunches the app to deliver completion events for a
    /// background URLSession. We stash the completion handler and hand it to
    /// the fetcher, which calls it from urlSessionDidFinishEvents.
    func application(_ application: UIApplication,
                     handleEventsForBackgroundURLSession identifier: String,
                     completionHandler: @escaping () -> Void) {
        BackgroundVehicleFetcher.shared.handleBackgroundEvents(completionHandler: completionHandler)
    }

    // MARK: UISceneSession Lifecycle

    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }

    func application(_ application: UIApplication,
                     didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {}
}
