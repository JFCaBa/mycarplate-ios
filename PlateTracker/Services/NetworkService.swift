//
//  NetworkService.swift
//  PlateTracker
//

import Foundation
import Combine

enum NetworkError: Error, LocalizedError {
    case invalidURL
    case requestFailed(Error)
    case invalidResponse(statusCode: Int)
    case decodingFailed(Error)
    case apiError(String)
    case rateLimited(retryAfterSeconds: Int)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .requestFailed(let error):
            return "Request failed: \(error.localizedDescription)"
        case .invalidResponse(let code):
            return "Server error (HTTP \(code))"
        case .decodingFailed:
            return "Could not read server response"
        case .apiError(let message):
            return message
        case .rateLimited(let seconds):
            return "Rate limited — retry in \(seconds)s"
        }
    }
}

final class NetworkService {

    static let shared = NetworkService()
    private let baseURL = "https://mycarplate.online"
    private let apiKey = "pl_live_fb11d100809bcb313580bad4801bedd76ca8fc8559d654514e6f01126d50aa15"

    private init() {}

    func fetchVehicle(plate: String, country: String = "ES") -> AnyPublisher<VehicleData, NetworkError> {
        let encodedPlate = plate.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? plate
        let urlString = "\(baseURL)/api/v1/vehicle?plate=\(encodedPlate)&country=\(country)"

        guard let url = URL(string: urlString) else {
            return Fail(error: NetworkError.invalidURL).eraseToAnyPublisher()
        }

        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")

        return URLSession.shared.dataTaskPublisher(for: request)
            .tryMap { result -> Data in
                guard let httpResponse = result.response as? HTTPURLResponse else {
                    throw NetworkError.invalidResponse(statusCode: 0)
                }
                print("[Network] \(plate) HTTP \(httpResponse.statusCode) (\(result.data.count) bytes)")
                guard (200...299).contains(httpResponse.statusCode) else {
                    if httpResponse.statusCode == 429 {
                        let retryAfter = (try? JSONDecoder().decode(RateLimitResponse.self, from: result.data))?.retryAfterSeconds ?? 60
                        throw NetworkError.rateLimited(retryAfterSeconds: retryAfter)
                    }
                    if let apiResponse = try? JSONDecoder().decode(ApiResponse.self, from: result.data),
                       let errorMessage = apiResponse.error {
                        throw NetworkError.apiError(errorMessage)
                    }
                    throw NetworkError.invalidResponse(statusCode: httpResponse.statusCode)
                }
                return result.data
            }
            .tryMap { data -> VehicleData in
                let response: ApiResponse
                do {
                    response = try JSONDecoder().decode(ApiResponse.self, from: data)
                } catch {
                    let raw = String(data: data.prefix(500), encoding: .utf8) ?? "<binary>"
                    print("[Network] ❌ Decode failed for \(plate): \(error)\nRaw: \(raw)")
                    throw NetworkError.decodingFailed(error)
                }
                guard response.success, let vehicleData = response.data else {
                    throw NetworkError.apiError(response.error ?? "Vehicle not found")
                }
                return vehicleData
            }
            .mapError { error in
                if let networkError = error as? NetworkError {
                    return networkError
                } else {
                    return NetworkError.requestFailed(error)
                }
            }
            .eraseToAnyPublisher()
    }

    func fetch<T: Decodable>(urlString: String) -> AnyPublisher<T, NetworkError> {
        guard let url = URL(string: urlString) else {
            return Fail(error: NetworkError.invalidURL).eraseToAnyPublisher()
        }

        return URLSession.shared.dataTaskPublisher(for: url)
            .tryMap { result -> Data in
                guard let httpResponse = result.response as? HTTPURLResponse,
                      (200...299).contains(httpResponse.statusCode) else {
                    throw NetworkError.invalidResponse(statusCode: 0)
                }
                return result.data
            }
            .decode(type: T.self, decoder: JSONDecoder())
            .mapError { error in
                if let decodingError = error as? DecodingError {
                    return NetworkError.decodingFailed(decodingError)
                } else {
                    return NetworkError.requestFailed(error)
                }
            }
            .eraseToAnyPublisher()
    }
}
