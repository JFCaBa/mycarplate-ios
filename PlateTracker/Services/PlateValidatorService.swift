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
        // EU stars symbol read as the literal letters
        "EU",
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

        // Pass 1: strip a known EU-band token if the remainder validates.
        for length in (1...maxStrip).reversed() {
            let prefix = String(raw.prefix(length))
            guard euBandPrefixes.contains(prefix) else { continue }
            let stripped = String(raw.dropFirst(length))
            if isValid(plate: stripped, for: country) {
                return stripped
            }
        }

        // Pass 2 (Spain only): strip any 1-4 leading letters when the
        // remainder is a STRICT modern plate (4 digits + 3 consonants). The
        // strict shape is specific enough that any letters in front of it
        // are virtually always EU-band noise that the whitelist didn't
        // anticipate (X, R, K, etc.). The historic motorcycle pattern is
        // unaffected — its remainder starts with a letter, not a digit, so
        // it can't accidentally match the modern shape.
        if country == .spain {
            for length in (1...maxStrip).reversed() {
                let prefix = String(raw.prefix(length))
                guard prefix.allSatisfy({ $0.isLetter }) else { continue }
                let stripped = String(raw.dropFirst(length))
                if stripped.range(of: #"^\d{4}[BCDFGHJKLMNPRSTVWXYZ]{3}$"#,
                                  options: .regularExpression) != nil {
                    return stripped
                }
            }
        }

        return raw
    }

    // Mirrors api/src/providers/countryDetector.ts, with iOS-side tightenings:
    // a historic two-line motorcycle pattern, an E/D-prefix reject in isValid
    // (see below), and the omission of two patterns that admit OCR noise — the
    // E-trailer `^E\d{4}[A-Z]$` (unreachable behind the prefix guard) and the
    // catch-all `^[A-Z]{1,2}\d{4}[A-Z]{3}$` (matches non-format reads like
    // X0662CRV; legitimate prefixed reads are recovered by cleanEUBandPrefix).
    private static let patterns: [PlateCountry: [String]] = [
        .spain: [
            #"^\d{4}[BCDFGHJKLMNPRSTVWXYZ]{3}$"#,
            #"^[A-Z]{1,2}\d{4}[A-Z]{1,2}$"#,
            #"^[SPV]\d{4}[A-Z]{3}$"#,
            #"^H\d{4}[A-Z]{3}$"#,
            #"^H[A-Z]{1,2}\d{4}$"#,
            // Historic two-line motorcycle/old-format: province + series letters
            // on top, 4 digits below — joined as e.g. GRAP7726 or MAB1234.
            // Bound to 3-4 letters: 2-letter forms (e.g. LE7302) are
            // overwhelmingly OCR noise rather than real pre-1971 plates.
            #"^[A-Z]{3,4}\d{4}$"#,
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
        // No legitimate Spanish province code or modern format starts with E
        // or D; if a "valid"-looking plate begins with one, it's almost
        // always the EU blue band's country glyph (E for España, sometimes
        // misread as D) bleeding into Vision's read. Reject up front so a
        // post-strip residue like "U0662CRV" can't sneak through either.
        if country == .spain && (plate.hasPrefix("E") || plate.hasPrefix("D")) {
            return false
        }
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
