//
//  SleepOverlayViewController.swift
//  PlateTracker
//

import UIKit

/// Full-screen black overlay that simulates the phone being asleep while the
/// scan pipeline keeps running underneath. Hosted in its own UIWindow so it
/// covers the navigation bar, tab bar, and status bar.
final class SleepOverlayViewController: UIViewController {

    var onDoubleTap: (() -> Void)?

    private let hintLabel: UILabel = {
        let label = UILabel()
        label.text = "Double-tap to wake"
        label.textColor = UIColor.white.withAlphaComponent(0.5)
        label.font = .preferredFont(forTextStyle: .footnote)
        label.textAlignment = .center
        label.alpha = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        view.addSubview(hintLabel)
        NSLayoutConstraint.activate([
            hintLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            hintLabel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -32),
        ])

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap))
        doubleTap.numberOfTapsRequired = 2
        view.addGestureRecognizer(doubleTap)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Brief hint so the user remembers how to dismiss; fades to invisible.
        UIView.animate(withDuration: 0.3, animations: { [weak self] in
            self?.hintLabel.alpha = 1
        }, completion: { [weak self] _ in
            UIView.animate(withDuration: 0.6, delay: 1.5, options: [], animations: {
                self?.hintLabel.alpha = 0
            })
        })
    }

    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }

    @objc private func handleDoubleTap() {
        onDoubleTap?()
    }
}
