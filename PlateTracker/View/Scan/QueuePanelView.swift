//
//  QueuePanelView.swift
//  PlateTracker
//

import UIKit
import Combine

final class QueuePanelView: UIView {

    var onDeleteRequested: ((String) -> Void)?

    private let tableView = UITableView(frame: .zero, style: .plain)
    private var items: [PlateQueueItem] = []
    private static let cellReuseID = "QueueRowCell"

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    func update(items: [PlateQueueItem]) {
        self.items = items
        tableView.reloadData()
    }

    private func setup() {
        backgroundColor = UIColor.black.withAlphaComponent(0.55)
        layer.cornerRadius = 12
        clipsToBounds = true

        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = .clear
        tableView.separatorColor = UIColor.white.withAlphaComponent(0.2)
        tableView.separatorInset = UIEdgeInsets(top: 0, left: 12, bottom: 0, right: 12)
        tableView.rowHeight = 44
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(QueueRowCell.self, forCellReuseIdentifier: Self.cellReuseID)
        addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: topAnchor),
            tableView.leadingAnchor.constraint(equalTo: leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    private func presentDeleteSheet(for plate: String) {
        guard let viewController = findOwningViewController() else { return }
        let sheet = UIAlertController(title: plate, message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            self?.onDeleteRequested?(plate)
        })
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        viewController.present(sheet, animated: true)
    }

    private func findOwningViewController() -> UIViewController? {
        var next: UIResponder? = self
        while let r = next {
            if let vc = r as? UIViewController { return vc }
            next = r.next
        }
        return nil
    }
}

extension QueuePanelView: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        items.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: Self.cellReuseID, for: indexPath) as! QueueRowCell
        cell.configure(with: items[indexPath.row])
        return cell
    }
}

extension QueuePanelView: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let item = items[indexPath.row]
        guard item.state == .pending else { return }
        presentDeleteSheet(for: item.plate)
    }
}

private final class QueueRowCell: UITableViewCell {
    private let plateLabel = UILabel()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let pendingIcon = UIImageView(image: UIImage(systemName: "ellipsis.circle"))

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        contentView.backgroundColor = .clear

        plateLabel.translatesAutoresizingMaskIntoConstraints = false
        plateLabel.textColor = .white
        plateLabel.font = UIFont.monospacedSystemFont(ofSize: 15, weight: .bold)
        contentView.addSubview(plateLabel)

        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.color = .white
        contentView.addSubview(spinner)

        pendingIcon.translatesAutoresizingMaskIntoConstraints = false
        pendingIcon.tintColor = UIColor.white.withAlphaComponent(0.8)
        pendingIcon.contentMode = .scaleAspectFit
        contentView.addSubview(pendingIcon)

        NSLayoutConstraint.activate([
            plateLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            plateLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            spinner.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            spinner.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            pendingIcon.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            pendingIcon.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            pendingIcon.widthAnchor.constraint(equalToConstant: 20),
            pendingIcon.heightAnchor.constraint(equalToConstant: 20),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    func configure(with item: PlateQueueItem) {
        plateLabel.text = item.plate
        switch item.state {
        case .processing:
            pendingIcon.isHidden = true
            spinner.isHidden = false
            spinner.startAnimating()
        case .pending:
            spinner.stopAnimating()
            spinner.isHidden = true
            pendingIcon.isHidden = false
        }
    }
}
