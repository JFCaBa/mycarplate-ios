//
//  ScanRecognitionConfig.swift
//  PlateTracker
//

import Foundation

/// User-tunable confidence threshold for the OCR triggers.
///
/// Both the live `.fast` Vision pass (which decides when to capture a frame)
/// and the `.accurate` follow-up pass (which decides what text to keep) reject
/// observations and candidates below this value. Lowering it makes the camera
/// fire on more frames; raising it filters out borderline reads.
enum ScanRecognitionConfig {

    static let confidenceDefault: Float = 0.75
    static let confidenceRange: ClosedRange<Float> = 0.5...0.95

    private static let confidenceKey = "plateRecognitionConfidence"

    static var confidence: Float {
        guard UserDefaults.standard.object(forKey: confidenceKey) != nil else {
            return confidenceDefault
        }
        return UserDefaults.standard.float(forKey: confidenceKey)
    }

    static func setConfidence(_ value: Float) {
        let clamped = min(max(value, confidenceRange.lowerBound), confidenceRange.upperBound)
        UserDefaults.standard.set(clamped, forKey: confidenceKey)
    }
}
