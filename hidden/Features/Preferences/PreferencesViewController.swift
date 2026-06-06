//
//  ViewController.swift
//  vanillaClone
//
//  Created by Thanh Nguyen on 1/24/19.
//  Copyright © 2019 Dwarves Foundation. All rights reserved.
//

import Cocoa
import Carbon
import HotKey

class PreferencesViewController: NSViewController {


    //MARK: - Outlets
    @IBOutlet weak var textFieldTitle: NSTextField!

    @IBOutlet weak var statusBarStackView: NSStackView!
    @IBOutlet weak var arrowPointToHiddenImage: NSImageView!
    @IBOutlet weak var arrowPointToAlwayHiddenImage: NSImageView!
    @IBOutlet weak var lblAlwayHidden: NSTextField!



    @IBOutlet weak var checkBoxAutoHide: NSButton!
    @IBOutlet weak var checkBoxLogin: NSButton!
    @IBOutlet weak var checkBoxShowPreferences: NSButton!
    @IBOutlet weak var checkBoxShowAlwaysHiddenSection: NSButton!

    @IBOutlet weak var checkBoxUseFullStatusbar: NSButton!
    @IBOutlet weak var timePopup: NSPopUpButton!

    @IBOutlet weak var btnClear: NSButton!
    @IBOutlet weak var btnShortcut: NSButton!

    private var tutorialArrowConstraints: [NSLayoutConstraint] = []

    public var listening = false {
        didSet {
            let isHighlight = listening

            DispatchQueue.main.async { [weak self] in
                self?.btnShortcut.highlight(isHighlight)
            }
        }
    }

    //MARK: - VC Life cycle
    override func viewDidLoad() {
        super.viewDidLoad()
        updateData()
        loadHotkey()
        createTutorialView()
        NotificationCenter.default.addObserver(self, selector: #selector(updateData), name: .prefsChanged, object: nil)
    }

    static func initWithStoryboard() -> PreferencesViewController {
        guard let vc = NSStoryboard(name:"Main", bundle: nil).instantiateController(withIdentifier: "prefVC") as? PreferencesViewController else {
            fatalError("Could not instantiate PreferencesViewController from storyboard with identifier 'prefVC'")
        }
        return vc
    }

    //MARK: - Actions
    @IBAction func loginCheckChanged(_ sender: NSButton) {
        Preferences.isAutoStart = sender.state == .on
    }

    @IBAction func autoHideCheckChanged(_ sender: NSButton) {
        Preferences.isAutoHide = sender.state == .on
    }

    @IBAction func showPreferencesChanged(_ sender: NSButton) {
        Preferences.isShowPreference = sender.state == .on
    }


    @IBAction func showAlwaysHiddenSectionChanged(_ sender: NSButton) {
        Preferences.alwaysHiddenSectionEnabled = sender.state == .on
        createTutorialView()
    }
    @IBAction func useFullStatusBarOnExpandChanged(_ sender: NSButton) {
        Preferences.useFullStatusBarOnExpandEnabled = sender.state == .on
    }


    @IBAction func timePopupDidSelected(_ sender: NSPopUpButton) {
        let selectedIndex = sender.indexOfSelectedItem
        if let selectedInSecond = SelectedSecond(rawValue: selectedIndex)?.toSeconds() {
            Preferences.numberOfSecondForAutoHide = selectedInSecond
        }
    }

    // When the set shortcut button is pressed start listening for the new shortcut
    @IBAction func register(_ sender: Any) {
        listening = true
        view.window?.makeFirstResponder(nil)
    }

    // If the shortcut is cleared, clear the UI and tell AppDelegate to stop listening to the previous keybind.
    @IBAction func unregister(_ sender: Any?) {
        guard let appDelegate = NSApplication.shared.delegate as? AppDelegate else { return }
        appDelegate.hotKey = nil
        btnShortcut.title = "Set Shortcut".localized
        listening = false
        btnClear.isEnabled = false

        // Remove globalkey from userdefault
        Preferences.globalKey = nil
    }

    public func updateGlobalShortcut(_ event: NSEvent) {
        self.listening = false

        guard let characters = event.charactersIgnoringModifiers else {return}

        let newGlobalKeybind = GlobalKeybindPreferences(
            function: event.modifierFlags.contains(.function),
            control: event.modifierFlags.contains(.control),
            command: event.modifierFlags.contains(.command),
            shift: event.modifierFlags.contains(.shift),
            option: event.modifierFlags.contains(.option),
            capsLock: event.modifierFlags.contains(.capsLock),
            carbonFlags: event.modifierFlags.carbonFlags,
            characters: characters,
            keyCode: uint32(event.keyCode))

        Preferences.globalKey = newGlobalKeybind

        updateKeybindButton(newGlobalKeybind)
        btnClear.isEnabled = true

        guard let appDelegate = NSApplication.shared.delegate as? AppDelegate else { return }
        appDelegate.hotKey = HotKey(keyCombo: KeyCombo(carbonKeyCode: UInt32(event.keyCode), carbonModifiers: event.modifierFlags.carbonFlags))
    }

    public func updateModiferFlags(_ event: NSEvent) {
        let newGlobalKeybind = GlobalKeybindPreferences(
            function: event.modifierFlags.contains(.function),
            control: event.modifierFlags.contains(.control),
            command: event.modifierFlags.contains(.command),
            shift: event.modifierFlags.contains(.shift),
            option: event.modifierFlags.contains(.option),
            capsLock: event.modifierFlags.contains(.capsLock),
            carbonFlags: 0,
            characters: nil,
            keyCode: uint32(event.keyCode))

        updateModifierbindButton(newGlobalKeybind)

    }

    @objc private func updateData(){
        checkBoxUseFullStatusbar.state = Preferences.useFullStatusBarOnExpandEnabled ? .on : .off
        checkBoxLogin.state = Preferences.isAutoStart ? .on : .off
        checkBoxAutoHide.state = Preferences.isAutoHide ? .on : .off
        checkBoxShowPreferences.state = Preferences.isShowPreference ? .on : .off
        checkBoxShowAlwaysHiddenSection.state = Preferences.alwaysHiddenSectionEnabled ? .on : .off
        timePopup.selectItem(at: SelectedSecond.secondToPosition(seconds: Preferences.numberOfSecondForAutoHide))
    }

    private func loadHotkey() {
        if let globalKey = Preferences.globalKey {
            updateKeybindButton(globalKey)
            updateClearButton(globalKey)
        }
    }

    // Set the shortcut button to show the keys to press
    private func updateKeybindButton(_ globalKeybindPreference : GlobalKeybindPreferences) {
        btnShortcut.title = globalKeybindPreference.description

        // Reject shortcuts with no modifier keys (description is just the key character)
        let hasModifier = globalKeybindPreference.function || globalKeybindPreference.control ||
                          globalKeybindPreference.command || globalKeybindPreference.shift ||
                          globalKeybindPreference.option
        if !hasModifier {
            unregister(nil)
        }
    }

    // Set the shortcut button to show the modifier to press
      private func updateModifierbindButton(_ globalKeybindPreference : GlobalKeybindPreferences) {
          btnShortcut.title = globalKeybindPreference.description

          if globalKeybindPreference.description.isEmpty {
              unregister(nil)
          }
      }

    // If a keybind is set, allow users to clear it by enabling the clear button.
    private func updateClearButton(_ globalKeybindPreference : GlobalKeybindPreferences?) {
        btnClear.isEnabled = globalKeybindPreference != nil
    }
}

//MARK: - Show tutorial
extension PreferencesViewController {

    func createTutorialView() {
        if Preferences.alwaysHiddenSectionEnabled {
            alwayHideStatusBar()
        }else {
            hideStatusBar()
        }
    }

    func hideStatusBar() {
        lblAlwayHidden.isHidden = true
        arrowPointToAlwayHiddenImage.isHidden = true
        let imageWidth: CGFloat = 16

        let imageViews = addStatusBarTutorialImages(
            ["ico_1","ico_2","ico_3","seprated", "ico_collapse","ico_4","ico_5","ico_6","ico_7"],
            imageWidth: imageWidth
        )
        updateTutorialArrowConstraints([
            arrowPointToHiddenImage.centerXAnchor.constraint(equalTo: imageViews["seprated"]?.centerXAnchor ?? statusBarStackView.centerXAnchor)
        ])
        arrowPointToHiddenImage.isHidden = imageViews["seprated"] == nil
    }

    func alwayHideStatusBar() {
        lblAlwayHidden.isHidden = false
        let imageWidth: CGFloat = 16

        let imageViews = addStatusBarTutorialImages(
            ["ico_1","ico_2","ico_3","ico_4", "seprated_1","ico_5","ico_6","seprated", "ico_collapse","ico_7"],
            imageWidth: imageWidth
        )
        updateTutorialArrowConstraints([
            arrowPointToAlwayHiddenImage.centerXAnchor.constraint(equalTo: imageViews["seprated_1"]?.centerXAnchor ?? statusBarStackView.centerXAnchor),
            arrowPointToHiddenImage.centerXAnchor.constraint(equalTo: imageViews["seprated"]?.centerXAnchor ?? statusBarStackView.centerXAnchor)
        ])
        arrowPointToAlwayHiddenImage.isHidden = imageViews["seprated_1"] == nil
        arrowPointToHiddenImage.isHidden = imageViews["seprated"] == nil
    }

    private func addStatusBarTutorialImages(_ imageNames: [String], imageWidth: CGFloat) -> [String: NSImageView] {
        updateTutorialArrowConstraints([])
        statusBarStackView.removeAllArrangedViews()

        var imageViews: [String: NSImageView] = [:]
        for imageName in imageNames {
            guard let image = NSImage(named: imageName) else { continue }

            let imageView = NSImageView(image: image)
            statusBarStackView.addArrangedSubview(imageView)
            imageView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                imageView.widthAnchor.constraint(equalToConstant: imageWidth),
                imageView.heightAnchor.constraint(equalToConstant: imageWidth)
            ])
            if #available(OSX 10.14, *) {
                imageView.contentTintColor = .labelColor
            }
            imageViews[imageName] = imageView
        }

        let dateTimeLabel = NSTextField()
        dateTimeLabel.stringValue = Date.dateString() + " " + Date.timeString()
        dateTimeLabel.translatesAutoresizingMaskIntoConstraints = false
        dateTimeLabel.isBezeled = false
        dateTimeLabel.isEditable = false
        dateTimeLabel.sizeToFit()
        dateTimeLabel.backgroundColor = .clear
        statusBarStackView.addArrangedSubview(dateTimeLabel)
        NSLayoutConstraint.activate([
            dateTimeLabel.heightAnchor.constraint(equalToConstant: imageWidth)
        ])

        return imageViews
    }

    private func updateTutorialArrowConstraints(_ constraints: [NSLayoutConstraint]) {
        NSLayoutConstraint.deactivate(tutorialArrowConstraints)
        tutorialArrowConstraints = constraints
        NSLayoutConstraint.activate(tutorialArrowConstraints)
    }

    @IBAction func btnAlwayHiddenHelpPressed(_ sender: NSButton) {
        self.showHowToUseAlwayHiddenPopover(sender: sender)
    }

    private func showHowToUseAlwayHiddenPopover(sender: NSButton) {
        let controller = NSViewController()
        let label = NSTextField()
        let text = NSLocalizedString("Tutorial text", comment: "Step by step tutorial")

        label.stringValue = text
        label.isBezeled = false
        label.isEditable = false
        let view = NSView()
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: view.topAnchor),
            label.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            label.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            label.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        label.translatesAutoresizingMaskIntoConstraints = false
        controller.view = view

        let popover = NSPopover()
        popover.contentViewController = controller
        popover.contentSize = controller.view.frame.size

        popover.behavior = .transient
        popover.animates = true

        popover.show(relativeTo: self.view.bounds, of: sender , preferredEdge: NSRectEdge.maxX)
    }
}
