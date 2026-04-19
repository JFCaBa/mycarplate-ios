//
//  ScanCropConfig.swift
//  PlateTracker
//

import CoreGraphics
import Foundation

/// User-tunable multipliers for the crop region around a detected plate,
/// expressed relative to the plate's bounding box. Persisted in UserDefaults.
///
/// - `width`: horizontal span, centered on the plate. `width = 4` means the
///   crop is 4× the plate width (2× on each side of its center).
/// - `above`: extra height above the plate, in plate-heights.
///   `above = 2.5` means 2.5× the plate height is captured above the plate's
///   top edge (for hood / grille / taillights).
/// - `below`: extra height below the plate, in plate-heights.
enum ScanCropConfig {

    static let widthDefault: CGFloat = 4.0
    static let aboveDefault: CGFloat = 2.5
    static let belowDefault: CGFloat = 1.0

    static let widthRange: ClosedRange<Float> = 1.5...6.0
    static let aboveRange: ClosedRange<Float> = 0.0...5.0
    static let belowRange: ClosedRange<Float> = 0.0...3.0

    private static let widthKey = "plateCropWidthMultiplier"
    private static let aboveKey = "plateCropAboveMultiplier"
    private static let belowKey = "plateCropBelowMultiplier"

    static var width: CGFloat { read(widthKey, default: widthDefault) }
    static var above: CGFloat { read(aboveKey, default: aboveDefault) }
    static var below: CGFloat { read(belowKey, default: belowDefault) }

    static func setWidth(_ value: CGFloat) { write(widthKey, value: value) }
    static func setAbove(_ value: CGFloat) { write(aboveKey, value: value) }
    static func setBelow(_ value: CGFloat) { write(belowKey, value: value) }

    private static func read(_ key: String, default defaultValue: CGFloat) -> CGFloat {
        guard UserDefaults.standard.object(forKey: key) != nil else { return defaultValue }
        return CGFloat(UserDefaults.standard.double(forKey: key))
    }

    private static func write(_ key: String, value: CGFloat) {
        UserDefaults.standard.set(Double(value), forKey: key)
    }
}
