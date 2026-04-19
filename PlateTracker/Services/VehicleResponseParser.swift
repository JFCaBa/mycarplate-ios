//
//  VehicleResponseParser.swift
//  PlateTracker
//

import Foundation

/// Pure helper: maps an HTTP response + body into a `PlateLookupOutcome`.
/// Used by both the foreground Combine path (NetworkService) and the
/// background URLSession path (BackgroundVehicleFetcher) so they agree on
/// success / rate-limit / failure classification.
enum VehicleResponseParser {

    static func parse(statusCode: Int, data: Data, plate: String) -> PlateLookupOutcome {
        print("[Parser] \(plate) HTTP \(statusCode) (\(data.count) bytes)")

        guard (200...299).contains(statusCode) else {
            if statusCode == 429 {
                let retryAfter = (try? JSONDecoder().decode(RateLimitResponse.self, from: data))?.retryAfterSeconds ?? 60
                return .rateLimited(retryAfterSeconds: retryAfter)
            }
            return .failure
        }

        let response: ApiResponse
        do {
            response = try JSONDecoder().decode(ApiResponse.self, from: data)
        } catch {
            let raw = String(data: data.prefix(500), encoding: .utf8) ?? "<binary>"
            print("[Parser] ❌ Decode failed for \(plate): \(error)\nRaw: \(raw)")
            return .failure
        }
        guard response.success, let vehicleData = response.data else {
            return .failure
        }
        return .success(vehicleData)
    }
}
