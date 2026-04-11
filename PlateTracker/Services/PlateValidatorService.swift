//
//  PlateValidatorService.swift
//  PlateTracker
//

import Foundation

enum PlateCountry: String, CaseIterable {
    case spain = "ES"
    case uk = "UK"
    case netherlands = "NL"
    case norway = "NO"
}

final class PlateValidator {

    private static let patterns: [PlateCountry: [String]] = [
        .spain: [
            #"^[0-9]{4}\s?[A-Z]{3}$"#,
            #"^[A-Z]{1,2}\s?[0-9]{4}\s?[A-Z]{0,3}$"#
        ],
        .uk: [
            #"^[A-Z]{2}[0-9]{2}\s?[A-Z]{3}$"#
        ],
        .netherlands: [
            #"^[A-Z0-9]{2,3}[-\s]?[A-Z0-9]{2,3}[-\s]?[A-Z0-9]{2,3}$"#
        ],
        .norway: [
            #"^[A-Z]{2}\s?[0-9]{4,5}$"#
        ]
    ]

    static func isValid(plate: String, for country: PlateCountry) -> Bool {
        guard let countryPatterns = patterns[country] else { return false }
        return countryPatterns.contains { pattern in
            plate.range(of: pattern, options: .regularExpression) != nil
        }
    }

    static func detectCountry(plate: String) -> PlateCountry? {
        for country in PlateCountry.allCases {
            if isValid(plate: plate, for: country) {
                return country
            }
        }
        return nil
    }
}
