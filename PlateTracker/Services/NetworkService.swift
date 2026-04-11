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
        }
    }
}

final class NetworkService {

    static let shared = NetworkService()
    private let baseURL = "https://mycarplate.online"

    private init() {}

    func fetchVehicle(plate: String, country: String = "ES") -> AnyPublisher<VehicleData, NetworkError> {
        let encodedPlate = plate.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? plate
        let urlString = "\(baseURL)/api/v1/vehicle?plate=\(encodedPlate)&country=\(country)"

        guard let url = URL(string: urlString) else {
            return Fail(error: NetworkError.invalidURL).eraseToAnyPublisher()
        }

        return URLSession.shared.dataTaskPublisher(for: url)
            .tryMap { result -> Data in
                guard let httpResponse = result.response as? HTTPURLResponse else {
                    throw NetworkError.invalidResponse(statusCode: 0)
                }
                guard (200...299).contains(httpResponse.statusCode) else {
                    if let apiResponse = try? JSONDecoder().decode(ApiResponse.self, from: result.data),
                       let errorMessage = apiResponse.error {
                        throw NetworkError.apiError(errorMessage)
                    }
                    throw NetworkError.invalidResponse(statusCode: httpResponse.statusCode)
                }
                return result.data
            }
            .decode(type: ApiResponse.self, decoder: JSONDecoder())
            .tryMap { response -> VehicleData in
                guard response.success, let data = response.data else {
                    throw NetworkError.apiError(response.error ?? "Vehicle not found")
                }
                return data
            }
            .mapError { error in
                if let networkError = error as? NetworkError {
                    return networkError
                } else if let decodingError = error as? DecodingError {
                    return NetworkError.decodingFailed(decodingError)
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
