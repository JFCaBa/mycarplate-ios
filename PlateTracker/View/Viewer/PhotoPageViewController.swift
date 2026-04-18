//
//  PhotoPageViewController.swift
//  PlateTracker
//

import UIKit

protocol PhotoPageViewControllerDelegate: AnyObject {
    func photoPage(_ page: PhotoPageViewController, didChangeSightingIndex index: Int)
}

final class PhotoPageViewController: UIViewController {

    let record: PlateScanRecord
    private var sightingIndex: Int
    weak var delegate: PhotoPageViewControllerDelegate?

    private let photoView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFit
        iv.backgroundColor = .black
        return iv
    }()

    private let filmstrip: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.itemSize = CGSize(width: 36, height: 36)
        layout.minimumLineSpacing = 4
        layout.sectionInset = UIEdgeInsets(top: 6, left: 12, bottom: 6, right: 12)
        let cv = UICollectionView(frame: .zero, collectionViewLayout: layout)
        cv.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        cv.showsHorizontalScrollIndicator = false
        return cv
    }()

    init(record: PlateScanRecord, initialSightingIndex: Int) {
        self.record = record
        self.sightingIndex = initialSightingIndex
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupViews()
        loadCurrentPhoto(animated: false)
    }

    private func setupViews() {
        view.addSubview(photoView)
        view.addSubview(filmstrip)
        photoView.translatesAutoresizingMaskIntoConstraints = false
        filmstrip.translatesAutoresizingMaskIntoConstraints = false

        filmstrip.dataSource = self
        filmstrip.delegate = self
        filmstrip.register(FilmstripFrameCell.self, forCellWithReuseIdentifier: FilmstripFrameCell.reuseIdentifier)

        let filmstripVisible = record.sightings.count > 1

        NSLayoutConstraint.activate([
            photoView.topAnchor.constraint(equalTo: view.topAnchor),
            photoView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            photoView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            photoView.bottomAnchor.constraint(equalTo: filmstripVisible ? filmstrip.topAnchor : view.bottomAnchor),

            filmstrip.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            filmstrip.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            filmstrip.heightAnchor.constraint(equalToConstant: filmstripVisible ? 48 : 0),
            filmstrip.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -56), // leave room for toolbar
        ])

        filmstrip.isHidden = !filmstripVisible
    }

    func reloadFilmstrip() {
        filmstrip.reloadData()
    }

    private func loadCurrentPhoto(animated: Bool) {
        let sighting = record.sightings[sightingIndex]
        let activeFileName = sighting.editedPhotoFileName ?? sighting.photoFileName
        guard let fileName = activeFileName else {
            photoView.image = UIImage(systemName: "car.fill")
            photoView.tintColor = .secondaryLabel
            return
        }
        let crossfade = { [weak self] (image: UIImage?) in
            guard let self = self else { return }
            if animated && !UIAccessibility.isReduceMotionEnabled {
                UIView.transition(with: self.photoView, duration: 0.2, options: .transitionCrossDissolve) {
                    self.photoView.image = image ?? UIImage(systemName: "car.fill")
                }
            } else {
                self.photoView.image = image ?? UIImage(systemName: "car.fill")
            }
        }
        PhotoCache.shared.loadAsync(fileName: fileName, completion: crossfade)
    }
}

extension PhotoPageViewController: UICollectionViewDataSource, UICollectionViewDelegate {
    func collectionView(_ cv: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        record.sightings.count
    }

    func collectionView(_ cv: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = cv.dequeueReusableCell(withReuseIdentifier: FilmstripFrameCell.reuseIdentifier, for: indexPath) as! FilmstripFrameCell
        // Newest first → reverse the index when reading sightings.
        let sIdx = record.sightings.count - 1 - indexPath.item
        cell.configure(sighting: record.sightings[sIdx], isActive: sIdx == sightingIndex)
        return cell
    }

    func collectionView(_ cv: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let sIdx = record.sightings.count - 1 - indexPath.item
        sightingIndex = sIdx
        loadCurrentPhoto(animated: true)
        cv.reloadData()
        delegate?.photoPage(self, didChangeSightingIndex: sIdx)
    }
}

final class FilmstripFrameCell: UICollectionViewCell {
    static let reuseIdentifier = "FilmstripFrameCell"

    private let imageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        iv.layer.cornerRadius = 4
        iv.backgroundColor = .darkGray
        return iv
    }()

    private let noteDot: UIView = {
        let v = UIView()
        v.backgroundColor = .white
        v.layer.cornerRadius = 3
        v.layer.borderColor = UIColor.black.withAlphaComponent(0.5).cgColor
        v.layer.borderWidth = 0.5
        v.isHidden = true
        return v
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.addSubview(imageView)
        contentView.addSubview(noteDot)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        noteDot.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),

            noteDot.widthAnchor.constraint(equalToConstant: 6),
            noteDot.heightAnchor.constraint(equalToConstant: 6),
            noteDot.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -3),
            noteDot.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -3),
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(sighting: Sighting, isActive: Bool) {
        if let fileName = sighting.editedPhotoFileName ?? sighting.photoFileName {
            PhotoCache.shared.loadAsync(fileName: fileName) { [weak self] image in
                self?.imageView.image = image
            }
        } else {
            imageView.image = UIImage(systemName: "car.fill")
        }
        contentView.layer.borderColor = UIColor.white.cgColor
        contentView.layer.borderWidth = isActive ? 2 : 0
        contentView.layer.cornerRadius = 4
        contentView.layer.masksToBounds = true
        noteDot.isHidden = (sighting.note?.isEmpty ?? true)
    }
}
