//
//  MainTabViewController.swift
//  PlateTracker
//

import UIKit

@MainActor
final class MainTabBarController: UITabBarController {

    private let scanViewModel = ScanViewModel()

    override func viewDidLoad() {
        super.viewDidLoad()
        setupTabs()
        configureTabBarAppearance()
    }

    private func configureTabBarAppearance() {
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = .systemBackground

        tabBar.standardAppearance = appearance
        tabBar.scrollEdgeAppearance = appearance
    }

    private func setupTabs() {
        let scanVC = ScanViewController()
        scanVC.configure(with: scanViewModel)
        scanVC.tabBarItem = UITabBarItem(title: "Scan", image: UIImage(systemName: "camera"), tag: 0)

        let resultsVC = ResultsViewController()
        resultsVC.configure(with: scanViewModel)
        resultsVC.tabBarItem = UITabBarItem(title: "Results", image: UIImage(systemName: "list.bullet"), tag: 1)

        let mapVC = MapViewController()
        mapVC.configure(with: scanViewModel)
        mapVC.tabBarItem = UITabBarItem(title: "Map", image: UIImage(systemName: "map"), tag: 2)

        let settingsVC = SettingsViewController()
        settingsVC.configure(with: scanViewModel)
        settingsVC.tabBarItem = UITabBarItem(title: "Settings", image: UIImage(systemName: "gearshape"), tag: 3)

        viewControllers = [
            UINavigationController(rootViewController: scanVC),
            UINavigationController(rootViewController: resultsVC),
            UINavigationController(rootViewController: mapVC),
            UINavigationController(rootViewController: settingsVC)
        ]
    }
}
