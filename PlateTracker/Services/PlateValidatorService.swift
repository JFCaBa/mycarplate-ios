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

    /// Tokens that may appear on the EU blue band and bleed into Vision's read
    /// of the plate text — country codes plus Spanish regional badges. Single-
    /// letter country codes also catch common Vision mis-reads of the band
    /// glyph (e.g. "E" reads as "D" or "F" on some frames).
    private static let euBandPrefixes: Set<String> = [
        // Country codes
        "E", "ES", "F", "FR", "D", "DE", "GB", "UK", "NL",
        "N", "NO", "P", "PT", "I", "IT", "B", "BE", "A", "AT",
        "CH", "PL", "L", "LU", "DK", "S", "SE", "FIN", "IRL",
        // Spanish regional badges (sometimes prefixed with E)
        "CAT", "AND", "PV", "GAL", "EUS", "VAL", "EXT",
        "ECAT", "EAND", "EPV", "EGAL", "EEUS", "EVAL",
    ]

    /// Strips OCR noise from the EU blue band (country codes, regional identifiers
    /// like CAT, AND, PV, etc.) that Vision may read as part of the plate text.
    /// Only strips when the leading 1-4 chars match a known EU-band token AND
    /// the remainder is itself a valid plate — so historic plates like GRAP7726
    /// (where "GR" is a province code, not a band token) stay intact.
    static func cleanEUBandPrefix(_ raw: String) -> String {
        let maxStrip = min(4, raw.count - 4)
        guard maxStrip > 0 else { return raw }
        for length in (1...maxStrip).reversed() {
            let prefix = String(raw.prefix(length))
            guard euBandPrefixes.contains(prefix) else { continue }
            let stripped = String(raw.dropFirst(length))
            if detectCountry(plate: stripped) != nil {
                return stripped
            }
        }
        return raw
    }

    /// Country-specific variant: only strips if the remainder is valid for the given country.
    static func cleanEUBandPrefix(_ raw: String, for country: PlateCountry) -> String {
        let maxStrip = min(4, raw.count - 4)
        guard maxStrip > 0 else { return raw }
        for length in (1...maxStrip).reversed() {
            let prefix = String(raw.prefix(length))
            guard euBandPrefixes.contains(prefix) else { continue }
            let stripped = String(raw.dropFirst(length))
            if isValid(plate: stripped, for: country) {
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
            // Historic two-line motorcycle/old-format: province + series letters
            // on top, 4 digits below — joined as e.g. GRAP7726.
            #"^[A-Z]{2,4}\d{4}$"#,
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
