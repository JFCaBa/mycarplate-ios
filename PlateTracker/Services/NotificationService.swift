//
//  NotificationService.swift
//  PlateTracker
//

import Foundation
import UserNotifications

final class NotificationService {

    static let shared = NotificationService()
    private init() {}

    /// Asks the OS for alert permission if the status is still undetermined.
    /// Returns whether the app may currently post user-visible notifications.
    func requestAuthorizationIfNeeded(completion: ((Bool) -> Void)? = nil) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                    DispatchQueue.main.async { completion?(granted) }
                }
            case .authorized, .provisional, .ephemeral:
                DispatchQueue.main.async { completion?(true) }
            case .denied:
                DispatchQueue.main.async { completion?(false) }
            @unknown default:
                DispatchQueue.main.async { completion?(false) }
            }
        }
    }

    /// Posts an immediate banner for a repeat-spot event.
    func notifyRepeatSpot(plate: String) {
        let content = UNMutableNotificationContent()
        content.title = "Plate spotted again"
        content.body = "\(plate) seen at a new location"
        content.sound = .default
        // Unique ID per fire so iOS doesn't coalesce multiple sightings of the
        // same plate into a single banner.
        let request = UNNotificationRequest(
            identifier: "repeatSpot.\(plate).\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }
}
