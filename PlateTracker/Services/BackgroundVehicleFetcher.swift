//
//  BackgroundVehicleFetcher.swift
//  PlateTracker
//

import Foundation

/// Dispatches plate lookups through a background URLSession so they continue
/// (and can finish) even after the app is suspended or killed. One-at-a-time
/// semantics are still enforced at the `PlateLookupQueue` layer; this class
/// is a thin wrapper that owns the URLSession and routes delegate callbacks
/// back into the queue's `completionHandler`.
///
/// Lifecycle:
/// - `bootstrap()` is called once from AppDelegate on every launch so the
///   URLSession (with its configured identifier) is live before iOS delivers
///   any pending events.
/// - `handleBackgroundEvents(completionHandler:)` stores the OS-provided
///   handler; the delegate calls it from `urlSessionDidFinishEvents(...)`.
/// - `dispatch(plate:country:)` creates a download task. When it finishes,
///   the delegate parses the response and invokes `completionHandler`.
final class BackgroundVehicleFetcher: NSObject {

    static let shared = BackgroundVehicleFetcher()

    private static let sessionIdentifier = "com.mycarplate.lookups"
    private let baseURL = "https://mycarplate.online"
    private let apiKey = "pl_live_fb11d100809bcb313580bad4801bedd76ca8fc8559d654514e6f01126d50aa15"

    /// Set by the queue on app launch. Called on main for every task that
    /// finishes (success, failure, rate-limit, or network error).
    var completionHandler: ((_ plate: String, _ outcome: PlateLookupOutcome) -> Void)?

    /// Handed in by AppDelegate when the system relaunches us to deliver
    /// events. Called once all pending events drain.
    private var systemBackgroundCompletionHandler: (() -> Void)?

    /// Plates we've already reported for the current in-memory session.
    /// Prevents double-notify from didFinishDownloadingTo + didCompleteWithError.
    private var reportedPlates: Set<String> = []

    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: Self.sessionIdentifier)
        config.sessionSendsLaunchEvents = true
        config.isDiscretionary = false
        config.waitsForConnectivity = true
        // Large timeout — the Spanish API takes 20-40s per plate.
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 300
        return URLSession(configuration: config, delegate: self, delegateQueue: OperationQueue.main)
    }()

    private override init() { super.init() }

    /// Eagerly creates the URLSession so it's live before any background events
    /// arrive on relaunch.
    func bootstrap() {
        _ = session
    }

    /// Stash the OS completion handler from
    /// application(_:handleEventsForBackgroundURLSession:completionHandler:).
    func handleBackgroundEvents(completionHandler: @escaping () -> Void) {
        systemBackgroundCompletionHandler = completionHandler
    }

    /// Kick off a lookup. The `completionHandler` will fire once the task
    /// finishes, possibly across app launches.
    func dispatch(plate: String, country: String) {
        guard let url = buildURL(plate: plate, country: country) else {
            deliver(plate: plate, outcome: .failure)
            return
        }
        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        let task = session.downloadTask(with: request)
        task.taskDescription = plate
        task.resume()
    }

    private func buildURL(plate: String, country: String) -> URL? {
        let encodedPlate = plate.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? plate
        return URL(string: "\(baseURL)/api/v1/vehicle?plate=\(encodedPlate)&country=\(country)")
    }

    private func deliver(plate: String, outcome: PlateLookupOutcome) {
        guard !reportedPlates.contains(plate) else { return }
        reportedPlates.insert(plate)
        completionHandler?(plate, outcome)
    }
}

extension BackgroundVehicleFetcher: URLSessionDownloadDelegate {

    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        guard let plate = downloadTask.taskDescription else { return }
        let statusCode = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0
        // The file at `location` is deleted as soon as this method returns —
        // read it synchronously before dispatching back.
        let data = (try? Data(contentsOf: location)) ?? Data()
        let outcome = VehicleResponseParser.parse(statusCode: statusCode, data: data, plate: plate)
        deliver(plate: plate, outcome: outcome)
    }

    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    didCompleteWithError error: Error?) {
        guard let plate = task.taskDescription else { return }
        if let error = error {
            print("[BG-Fetch] \(plate) failed: \(error.localizedDescription)")
            deliver(plate: plate, outcome: .failure)
        }
        // Success path already handled in didFinishDownloadingTo; reportedPlates
        // de-dupes the repeated delivery attempt.
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        let handler = systemBackgroundCompletionHandler
        systemBackgroundCompletionHandler = nil
        handler?()
    }
}
