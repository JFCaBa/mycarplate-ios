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

    // Mirrors api/src/providers/countryDetector.ts exactly
    private static let patterns: [PlateCountry: [String]] = [
        .spain: [
            #"^\d{4}[BCDFGHJKLMNPRSTVWXYZ]{3}$"#,
            #"^[A-Z]{1,2}\d{4}[A-Z]{1,2}$"#,
            #"^[SPV]\d{4}[A-Z]{3}$"#,
            #"^E\d{4}[A-Z]$"#,
            #"^H\d{4}[A-Z]{3}$"#,
            #"^H[A-Z]{1,2}\d{4}$"#,
            #"^[A-Z]{1,2}\d{4}[A-Z]{3}$"#,
        ],
        .netherlands: [
            // With dashes (sidecodes 1-12)
            #"^[A-Z]{2}-\d{2}-\d{2}$"#,
            #"^\d{2}-\d{2}-[A-Z]{2}$"#,
            #"^\d{2}-[A-Z]{2}-\d{2}$"#,
            #"^[A-Z]{2}-[A-Z]{2}-\d{2}$"#,
            #"^\d{2}-[A-Z]{2}-[A-Z]{2}$"#,
            #"^[A-Z]{2}-\d{2}-[A-Z]{2}$"#,
            #"^\d-[A-Z]{3}-\d{2}$"#,
            #"^\d{2}-[A-Z]{3}-\d$"#,
            #"^[A-Z]{2}-\d{3}-[A-Z]$"#,
            #"^[A-Z]-\d{3}-[A-Z]{2}$"#,
            #"^[A-Z]{3}-\d{2}-[A-Z]$"#,
            #"^[A-Z]-\d{2}-[A-Z]{3}$"#,
            // Without dashes
            #"^[A-Z]{2}\d{4}$"#,
            #"^\d{4}[A-Z]{2}$"#,
            #"^[A-Z]{2}\d{2}[A-Z]{2}$"#,
            #"^\d{2}[A-Z]{2}\d{2}$"#,
            #"^\d[A-Z]{3}\d{2}$"#,
            #"^\d{2}[A-Z]{3}\d$"#,
            #"^[A-Z]{2}\d{3}[A-Z]$"#,
            #"^[A-Z]\d{3}[A-Z]{2}$"#,
            #"^[A-Z]{3}\d{2}[A-Z]$"#,
            #"^[A-Z]\d{2}[A-Z]{3}$"#,
        ],
        .uk: [
            #"^[A-Z]{2}\d{2}[A-Z]{3}$"#,
        ],
        .norway: [
            #"^[A-Z]{2}\d{3,5}$"#,
        ],
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
