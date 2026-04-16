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

    /// Strips OCR noise from the EU blue band (country codes, regional identifiers
    /// like CAT, AND, PV, etc.) that Vision may read as part of the plate text.
    /// Tries progressively shorter prefixes (up to 4 chars) — only strips when
    /// the remainder is itself a valid plate.
    static func cleanEUBandPrefix(_ raw: String) -> String {
        // Try stripping 1 to 4 leading characters (covers "E", "ES", "CAT", "ECAT", etc.)
        let maxStrip = min(4, raw.count - 4) // keep at least 4 chars for a valid plate
        guard maxStrip > 0 else { return raw }
        for length in (1...maxStrip).reversed() {
            let stripped = String(raw.dropFirst(length))
            if detectCountry(plate: stripped) != nil {
                return stripped
            }
        }
        return raw
    }

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
