//
//  NoteEditorViewController.swift
//  PlateTracker
//

import UIKit

final class NoteEditorViewController: UIViewController {

    typealias SaveHandler = (String?) -> Void

    private let initialText: String?
    private let onSave: SaveHandler

    private let textView: UITextView = {
        let tv = UITextView()
        tv.font = .preferredFont(forTextStyle: .body)
        tv.adjustsFontForContentSizeCategory = true
        tv.textContainerInset = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        return tv
    }()

    init(initialText: String?, onSave: @escaping SaveHandler) {
        self.initialText = initialText
        self.onSave = onSave
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Note"
        view.backgroundColor = .systemBackground
        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancelTapped))
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .save, target: self, action: #selector(saveTapped))

        view.addSubview(textView)
        textView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            textView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            textView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        textView.text = initialText
        textView.becomeFirstResponder()
    }

    @objc private func cancelTapped() { dismiss(animated: true) }

    @objc private func saveTapped() {
        let trimmed = textView.text.trimmingCharacters(in: .whitespacesAndNewlines)
        onSave(trimmed.isEmpty ? nil : trimmed)
        dismiss(animated: true)
    }
}
