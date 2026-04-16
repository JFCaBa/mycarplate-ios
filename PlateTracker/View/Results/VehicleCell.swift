//
//  VehicleCell.swift
//  PlateTracker
//

import UIKit

final class VehicleCell: UITableViewCell {

    static let reuseIdentifier = "VehicleCell"

    private(set) var fullImage: UIImage?

    private let vehicleImageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        iv.layer.cornerRadius = 8
        iv.backgroundColor = .secondarySystemBackground
        iv.tintColor = .secondaryLabel
        iv.isUserInteractionEnabled = true
        return iv
    }()

    private let plateLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 16, weight: .semibold)
        return label
    }()

    private let detailLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 13)
        label.textColor = .secondaryLabel
        return label
    }()

    private let sightingsLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 12)
        label.textColor = .tertiaryLabel
        return label
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews() {
        let tap = UITapGestureRecognizer(target: self, action: #selector(imageTapped))
        vehicleImageView.addGestureRecognizer(tap)

        let textStack = UIStackView(arrangedSubviews: [plateLabel, detailLabel, sightingsLabel])
        textStack.axis = .vertical
        textStack.spacing = 2

        let mainStack = UIStackView(arrangedSubviews: [vehicleImageView, textStack])
        mainStack.axis = .horizontal
        mainStack.spacing = 12
        mainStack.alignment = .center

        contentView.addSubview(mainStack)
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            vehicleImageView.widthAnchor.constraint(equalToConstant: 60),
            vehicleImageView.heightAnchor.constraint(equalToConstant: 45),
            mainStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            mainStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),
            mainStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            mainStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -40),
        ])
    }

    @objc private func imageTapped() {
        guard let image = fullImage else { return }
        NotificationCenter.default.post(name: .vehicleCellImageTapped, object: image)
    }

    func configure(with record: PlateScanRecord) {
        if let photoName = record.sightings.last?.photoFileName {
            let image = StorageService.shared.loadPhoto(fileName: photoName)
            vehicleImageView.image = image
            fullImage = image
        } else {
            vehicleImageView.image = UIImage(systemName: "car.fill")
            fullImage = nil
        }

        if let data = record.vehicleData {
            let makeModel = [data.make, data.model].compactMap { $0 }.joined(separator: " ")
            plateLabel.text = makeModel.isEmpty ? record.plate : "\(record.plate) — \(makeModel)"
            let details = [
                data.year.map { String($0) },
                data.color,
                data.fuelType
            ].compactMap { $0 }.joined(separator: " | ")
            detailLabel.text = details.isEmpty ? nil : details
        } else {
            plateLabel.text = record.plate
            detailLabel.text = nil
        }

        let count = record.sightings.count
        sightingsLabel.text = count == 1 ? "Seen 1 time" : "Seen \(count) times"

        accessoryType = .disclosureIndicator
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        vehicleImageView.image = nil
        fullImage = nil
        plateLabel.text = nil
        detailLabel.text = nil
        sightingsLabel.text = nil
    }
}

extension Notification.Name {
    static let vehicleCellImageTapped = Notification.Name("vehicleCellImageTapped")
}
