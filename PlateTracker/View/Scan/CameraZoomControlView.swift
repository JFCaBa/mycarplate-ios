//
//  CameraZoomControlView.swift
//  PlateTracker
//

import UIKit

/// iOS Camera-style zoom pill: a row of preset buttons (e.g. 0.5 · 1× · 2 · 3)
/// that sits centered above the shutter area. The active preset expands into
/// a filled circle showing the live zoom value (e.g. "1.4×"); inactive ones
/// shrink to small labels. Pan horizontally across the row to scrub
/// continuously between presets; tap a preset to snap to it.
final class CameraZoomControlView: UIView {

    var onZoomChanged: ((CGFloat, Bool) -> Void)?

    private let pillBackground = UIView()
    private let buttonStack = UIStackView()
    private var presetButtons: [UIButton] = []
    private var presetValues: [CGFloat] = []

    private var minZoomFactor: CGFloat = 1
    private var maxZoomFactor: CGFloat = 1
    private var currentZoomFactor: CGFloat = 1

    private var isScrubbing = false
    private var lastFeedbackPreset: Int?
    private let feedback = UISelectionFeedbackGenerator()

    private let accentColor = UIColor(red: 1.0, green: 0.84, blue: 0.15, alpha: 1.0)
    private let activeDiameter: CGFloat = 44
    private let inactiveDiameter: CGFloat = 30
    private let pillVerticalPadding: CGFloat = 6
    private let pillHorizontalPadding: CGFloat = 10

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        pillBackground.layer.cornerRadius = pillBackground.bounds.height / 2
    }

    /// `self` has a max-width constraint (≤320) but no minimum, so its bounds
    /// can be narrower than the visible pill. Without `clipsToBounds`, the
    /// subviews still draw correctly, but UIKit hit-testing only routes
    /// touches inside `self.bounds` — which is why taps on the pill weren't
    /// reaching the gesture recognizers. Extend the hit area to include the
    /// pill's frame so taps land on whichever preset the user pressed.
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        if super.point(inside: point, with: event) { return true }
        return pillBackground.frame.contains(point)
    }

    func configure(minZoomFactor: CGFloat, maxZoomFactor: CGFloat, initialZoomFactor: CGFloat) {
        // Trust the device's reported bounds; the caller has already clamped
        // to a sensible UX maximum.
        self.minZoomFactor = max(0.1, minZoomFactor)
        self.maxZoomFactor = max(self.minZoomFactor, maxZoomFactor)
        presetValues = makePresetValues()
        rebuildPresetButtons()
        setZoomFactor(initialZoomFactor, animated: false, emitChange: false)
    }

    func setZoomFactor(_ factor: CGFloat, animated: Bool, emitChange: Bool) {
        currentZoomFactor = clampedZoom(factor)
        updatePresetSelection(animated: animated)
        if emitChange {
            onZoomChanged?(currentZoomFactor, animated)
        }
    }
}

private extension CameraZoomControlView {

    func setup() {
        backgroundColor = .clear

        pillBackground.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        pillBackground.layer.cornerCurve = .continuous
        pillBackground.translatesAutoresizingMaskIntoConstraints = false
        pillBackground.isUserInteractionEnabled = false
        addSubview(pillBackground)

        buttonStack.axis = .horizontal
        buttonStack.alignment = .center
        buttonStack.distribution = .equalCentering
        buttonStack.spacing = 6
        buttonStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(buttonStack)

        // Pill grows with the stack — capped to active diameter + padding.
        let pillHeight = activeDiameter + pillVerticalPadding * 2
        NSLayoutConstraint.activate([
            buttonStack.centerXAnchor.constraint(equalTo: centerXAnchor),
            buttonStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            buttonStack.heightAnchor.constraint(equalToConstant: activeDiameter),

            pillBackground.centerXAnchor.constraint(equalTo: buttonStack.centerXAnchor),
            pillBackground.centerYAnchor.constraint(equalTo: buttonStack.centerYAnchor),
            pillBackground.heightAnchor.constraint(equalToConstant: pillHeight),
            pillBackground.leadingAnchor.constraint(equalTo: buttonStack.leadingAnchor, constant: -pillHorizontalPadding),
            pillBackground.trailingAnchor.constraint(equalTo: buttonStack.trailingAnchor, constant: pillHorizontalPadding),
        ])

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.maximumNumberOfTouches = 1
        addGestureRecognizer(pan)

        // Buttons are display-only — taps are routed through this recognizer
        // so they never compete with the pan gesture's internal tracking.
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        addGestureRecognizer(tap)
    }

    func rebuildPresetButtons() {
        presetButtons.forEach { $0.removeFromSuperview() }
        presetButtons.removeAll()

        for _ in presetValues.indices {
            let button = UIButton(type: .custom)
            button.translatesAutoresizingMaskIntoConstraints = false
            button.titleLabel?.adjustsFontSizeToFitWidth = true
            button.titleLabel?.minimumScaleFactor = 0.7
            button.titleLabel?.textAlignment = .center
            button.layer.cornerCurve = .continuous
            // Display-only — interactions handled by gesture recognizers on
            // the parent so the pan recognizer can't intercept the tap.
            button.isUserInteractionEnabled = false
            // Size constraints are updated in updatePresetSelection so the
            // active button can grow without disturbing the others.
            button.widthAnchor.constraint(equalToConstant: inactiveDiameter).isActive = true
            button.heightAnchor.constraint(equalToConstant: inactiveDiameter).isActive = true
            buttonStack.addArrangedSubview(button)
            presetButtons.append(button)
        }
        updatePresetSelection(animated: false)
    }

    func updatePresetSelection(animated: Bool) {
        guard !presetButtons.isEmpty else { return }
        let activeIndex = nearestPresetIndex(to: currentZoomFactor)

        let apply: () -> Void = { [self] in
            for (index, button) in presetButtons.enumerated() {
                let isActive = index == activeIndex
                let diameter = isActive ? activeDiameter : inactiveDiameter
                for c in button.constraints {
                    if c.firstAttribute == .width || c.firstAttribute == .height {
                        c.constant = diameter
                    }
                }
                button.layer.cornerRadius = diameter / 2
                button.backgroundColor = isActive
                    ? UIColor.black.withAlphaComponent(0.55)
                    : .clear
                button.titleLabel?.font = UIFont.monospacedDigitSystemFont(
                    ofSize: isActive ? 14 : 12,
                    weight: isActive ? .semibold : .medium
                )
                let title = isActive
                    ? Self.activeText(for: currentZoomFactor)
                    : Self.presetText(for: presetValues[index])
                button.setTitleColor(isActive ? accentColor : UIColor.white.withAlphaComponent(0.95), for: .normal)
                button.setTitle(title, for: .normal)
            }
            layoutIfNeeded()
        }

        if animated {
            UIView.animate(withDuration: 0.18, delay: 0, options: [.curveEaseOut, .beginFromCurrentState]) {
                apply()
            }
        } else {
            apply()
        }

        if isScrubbing, activeIndex != lastFeedbackPreset {
            feedback.selectionChanged()
            lastFeedbackPreset = activeIndex
        }
    }

    func nearestPresetIndex(to zoom: CGFloat) -> Int {
        guard !presetValues.isEmpty else { return 0 }
        var bestIndex = 0
        var bestDelta = CGFloat.greatestFiniteMagnitude
        for (index, value) in presetValues.enumerated() {
            let delta = abs(value - zoom)
            if delta < bestDelta {
                bestDelta = delta
                bestIndex = index
            }
        }
        return bestIndex
    }

    func makePresetValues() -> [CGFloat] {
        // Show 0.5× only if the device actually supports sub-1× (virtual
        // multi-cam with ultrawide). Otherwise the zoom would clamp to 1× and
        // the button would be a no-op.
        var values: [CGFloat] = []
        if minZoomFactor < 0.95 {
            values.append(0.5)
        }
        values.append(1)
        if maxZoomFactor >= 2 { values.append(2) }
        if maxZoomFactor >= 3 { values.append(3) }
        if maxZoomFactor >= 5 { values.append(5) }

        let trimmed = values.filter { $0 >= minZoomFactor - 0.01 && $0 <= maxZoomFactor + 0.01 }
        return trimmed.isEmpty ? [max(1, minZoomFactor)] : trimmed
    }

    @objc
    func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard !presetButtons.isEmpty else { return }
        let location = gesture.location(in: buttonStack)
        switch gesture.state {
        case .began:
            isScrubbing = true
            lastFeedbackPreset = nearestPresetIndex(to: currentZoomFactor)
            feedback.prepare()
            fallthrough
        case .changed:
            let zoom = zoomFactor(forStackPoint: location)
            setZoomFactor(zoom, animated: false, emitChange: true)
        default:
            isScrubbing = false
            lastFeedbackPreset = nil
            // Snap to the nearest preset on lift, like iOS Camera does when
            // the user releases without much horizontal travel.
            let snapTarget = presetValues[nearestPresetIndex(to: currentZoomFactor)]
            setZoomFactor(snapTarget, animated: true, emitChange: true)
        }
    }

    func handlePresetTap(at index: Int) {
        guard index >= 0, index < presetValues.count else { return }
        feedback.selectionChanged()
        setZoomFactor(presetValues[index], animated: true, emitChange: true)
    }

    @objc
    func handleTap(_ gesture: UITapGestureRecognizer) {
        guard !presetButtons.isEmpty else { return }
        let location = gesture.location(in: buttonStack)
        // Tap targets are generous: closest button center wins. This is
        // necessary because inactive presets are 30pt wide — smaller than the
        // 44pt HIG tap target — so we let the surrounding empty space route
        // to the nearest preset.
        var bestIndex = 0
        var bestDelta = CGFloat.greatestFiniteMagnitude
        for (index, button) in presetButtons.enumerated() {
            let delta = abs(button.center.x - location.x)
            if delta < bestDelta {
                bestDelta = delta
                bestIndex = index
            }
        }
        handlePresetTap(at: bestIndex)
    }

    /// Maps a horizontal point in the stack's coordinate space to a zoom
    /// factor by interpolating between the two nearest preset buttons. This
    /// keeps the scrub speed feeling natural across uneven preset spacing
    /// (0.5→1 is one stop, 1→2 is another, etc.).
    func zoomFactor(forStackPoint point: CGPoint) -> CGFloat {
        guard presetButtons.count >= 2 else { return presetValues.first ?? 1 }

        let centers: [CGFloat] = presetButtons.map { $0.center.x }
        if point.x <= centers.first! { return presetValues.first! }
        if point.x >= centers.last! { return presetValues.last! }

        for i in 0..<(centers.count - 1) {
            let xA = centers[i]
            let xB = centers[i + 1]
            if point.x >= xA, point.x <= xB {
                let span = max(xB - xA, 0.001)
                let t = (point.x - xA) / span
                return presetValues[i] + (presetValues[i + 1] - presetValues[i]) * t
            }
        }
        return currentZoomFactor
    }

    func clampedZoom(_ factor: CGFloat) -> CGFloat {
        min(max(factor, minZoomFactor), maxZoomFactor)
    }

    static func presetText(for value: CGFloat) -> String {
        if abs(value - value.rounded()) < 0.05 {
            return String(format: "%.0f", value)
        }
        return String(format: "%.1f", value)
    }

    static func activeText(for value: CGFloat) -> String {
        // Match iOS Camera: "1×" exactly at the preset, "1.4×" mid-scrub.
        if abs(value - value.rounded()) < 0.05 {
            return String(format: "%.0f×", value)
        }
        return String(format: "%.1f×", value)
    }
}
