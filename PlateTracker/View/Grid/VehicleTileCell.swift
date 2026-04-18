//
//  VehicleTileCell.swift
//  PlateTracker
//

import UIKit

final class VehicleTileCell: UICollectionViewCell {

    static let reuseIdentifier = "VehicleTileCell"

    private let imageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        iv.backgroundColor = .secondarySystemBackground
        return iv
    }()

    private let placeholderImageView: UIImageView = {
        let iv = UIImageView(image: UIImage(systemName: "car.fill"))
        iv.tintColor = .tertiaryLabel
        iv.contentMode = .center
        iv.isHidden = true
        return iv
    }()

    private let plateBadge: PaddedLabel = {
        let l = PaddedLabel()
        l.font = .systemFont(ofSize: 10, weight: .semibold)
        l.textColor = .white
        l.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        l.layer.cornerRadius = 4
        l.layer.masksToBounds = true
        return l
    }()

    private let countBadge: PaddedLabel = {
        let l = PaddedLabel()
        l.font = .systemFont(ofSize: 10, weight: .semibold)
        l.textColor = .white
        l.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        l.layer.cornerRadius = 8
        l.layer.masksToBounds = true
        l.isHidden = true
        return l
    }()

    private var currentFileName: String?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setupViews() {
        contentView.addSubview(imageView)
        contentView.addSubview(placeholderImageView)
        contentView.addSubview(plateBadge)
        contentView.addSubview(countBadge)

        for v in [imageView, placeholderImageView, plateBadge, countBadge] {
            v.translatesAutoresizingMaskIntoConstraints = false
        }

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),

            placeholderImageView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            placeholderImageView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),

            plateBadge.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 4),
            plateBadge.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),

            countBadge.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -4),
            countBadge.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
        ])
    }

    func configure(with record: PlateScanRecord) {
        plateBadge.text = " \(record.plate) "

        let count = record.sightings.count
        if count > 1 {
            countBadge.text = " ×\(count) "
            countBadge.isHidden = false
        } else {
            countBadge.isHidden = true
        }

        accessibilityLabel = Self.accessibilityLabel(for: record)

        if let fileName = record.sightings.last?.photoFileName {
            currentFileName = fileName
            placeholderImageView.isHidden = true
            imageView.image = nil
            PhotoCache.shared.loadAsync(fileName: fileName) { [weak self] image in
                guard self?.currentFileName == fileName else { return } // reused cell
                self?.imageView.image = image
                if image == nil {
                    self?.placeholderImageView.isHidden = false
                }
            }
        } else {
            currentFileName = nil
            imageView.image = nil
            placeholderImageView.isHidden = false
        }
    }

    private static func accessibilityLabel(for record: PlateScanRecord) -> String {
        let makeModel = [record.vehicleData?.make, record.vehicleData?.model].compactMap { $0 }.joined(separator: " ")
        let count = record.sightings.count
        let countText = count == 1 ? "seen 1 time" : "seen \(count) times"
        if makeModel.isEmpty {
            return "Plate \(record.plate), \(countText)"
        }
        return "\(makeModel), plate \(record.plate), \(countText)"
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        currentFileName = nil
        imageView.image = nil
        placeholderImageView.isHidden = true
        plateBadge.text = nil
        countBadge.text = nil
        countBadge.isHidden = true
    }
}

/// UILabel with insets so the dark badge background looks like a pill.
final class PaddedLabel: UILabel {
    var insets = UIEdgeInsets(top: 1, left: 5, bottom: 1, right: 5)
    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: insets))
    }
    override var intrinsicContentSize: CGSize {
        let s = super.intrinsicContentSize
        return CGSize(width: s.width + insets.left + insets.right,
                      height: s.height + insets.top + insets.bottom)
    }
}
