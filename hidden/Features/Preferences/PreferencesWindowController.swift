//
//  PreferencesWindowController.swift
//  Hidden Bar
//
//  Created by Phuc Le Dien on 2/22/19.
//  Copyright © 2019 Dwarves Foundation. All rights reserved.
//

import Cocoa

class PreferencesWindowController: NSWindowController {

    enum MenuSegment: Int {
        case general
        case about
    }

    static let shared: PreferencesWindowController = {
        guard let wc = NSStoryboard(name:"Main", bundle: nil).instantiateController(withIdentifier: "MainWindow") as? PreferencesWindowController else {
            fatalError("Could not instantiate PreferencesWindowController from storyboard with identifier 'MainWindow'")
        }
        return wc
    }()

    private var menuSegment: MenuSegment = .general {
        didSet {
            updateVC()
        }
    }

    private let preferencesVC = PreferencesViewController.initWithStoryboard()

    private let aboutVC = AboutViewController.initWithStoryboard()

    override func windowDidLoad() {
        super.windowDidLoad()
        updateVC()
    }

    override func keyDown(with event: NSEvent) {
        if let vc = self.contentViewController as? PreferencesViewController, vc.listening {
            vc.updateGlobalShortcut(event)
        } else {
            super.keyDown(with: event)
        }
    }

    override func flagsChanged(with event: NSEvent) {
        if let vc = self.contentViewController as? PreferencesViewController, vc.listening {
            vc.updateModiferFlags(event)
        } else {
            super.flagsChanged(with: event)
        }
    }

    @IBAction func switchSegment(_ sender: NSSegmentedControl) {
        guard let segment = MenuSegment(rawValue: sender.selectedSegment) else {return}
        menuSegment = segment
    }

    private func updateVC() {
        switch menuSegment {
        case .general:
            self.window?.contentViewController = preferencesVC
        case .about:
            self.window?.contentViewController = aboutVC
        }
    }

}
