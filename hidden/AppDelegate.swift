//
//  AppDelegate.swift
//  vanillaClone
//
//  Created by Thanh Nguyen on 1/24/19.
//  Copyright © 2019 Dwarves Foundation. All rights reserved.
//

import AppKit
import HotKey
import ServiceManagement

@NSApplicationMain

class AppDelegate: NSObject, NSApplicationDelegate{

    lazy var statusBarController = StatusBarController()

    var hotKey: HotKey? {
        didSet {
            guard let hotKey = hotKey else { return }

            hotKey.keyDownHandler = { [weak self] in
                self?.statusBarController.expandCollapseIfNeeded()
            }
        }
    }

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        registerDefaultValues()
        detectLTRLang()
        setupAutoStartApp()
        _ = statusBarController // Force lazy init after defaults/LTR are ready
        setupHotKey()
        openPreferencesIfNeeded()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.warnAboutConflictingMenuBarManagersIfNeeded()
        }
    }

    func openPreferencesIfNeeded() {
        if Preferences.isShowPreference {
            Util.showPrefWindow()
        }
    }

    func setupAutoStartApp() {
        removeLegacyLauncherLoginItem()
        Util.setUpAutoStart(isAutoStart: Preferences.isAutoStart)
    }

    private func removeLegacyLauncherLoginItem() {
        // Builds before the SMAppService migration registered a helper app in BTM;
        // macOS never garbage-collects that record (TN3111), so deauthorize it once.
        let migratedKey = "smAppServiceMigrated"
        guard !UserDefaults.standard.bool(forKey: migratedKey) else { return }
        SMLoginItemSetEnabled("com.dwarvesv.LauncherApplication" as CFString, false)
        UserDefaults.standard.set(true, forKey: migratedKey)
    }

    func registerDefaultValues() {
         UserDefaults.standard.register(defaults: [
            UserDefaults.Key.isAutoStart: false,
            UserDefaults.Key.isShowPreference: true,
            UserDefaults.Key.isAutoHide: true,
            UserDefaults.Key.numberOfSecondForAutoHide: 10.0,
            UserDefaults.Key.areSeparatorsHidden: false,
            UserDefaults.Key.alwaysHiddenSectionEnabled: false,
            UserDefaults.Key.useFullStatusBarOnExpandEnabled: false
         ])
    }

    func setupHotKey() {
        guard let globalKey = Preferences.globalKey else {return}
        hotKey = HotKey(keyCombo: KeyCombo(carbonKeyCode: globalKey.keyCode, carbonModifiers: globalKey.carbonFlags))
    }

    func detectLTRLang() {
        // Languages like Arabic uses right to left (RTL) writing direction,
        // so some behavier of the app needs to be changed in these cases

        Constant.isUsingLTRLanguage = (NSApplication.shared.userInterfaceLayoutDirection == .leftToRight)
    }

    private func warnAboutConflictingMenuBarManagersIfNeeded() {
        let conflictingApps: [String: String] = [
            "com.surteesstudios.Bartender": "Bartender",
            "com.sindresorhus.Bartender": "Bartender",
            "com.Mortennn.Dozer": "Dozer",
            "com.github.Mortennn.Dozer": "Dozer",
            "com.mortennn.Dozer": "Dozer",
            "com.jordanbaird.Ice": "Ice",
            "com.macpaw.CleanMyMac-setapp": "CleanMyMac Menu",
            "com.gaosun.BarTender": "iBar",
            "com.gaosun.iBar": "iBar",
            "com.HyperartFlow.Barbee": "Barbee",
            "com.sanebar.app": "SaneBar"
        ]

        let ownBundleIdentifier = Bundle.main.bundleIdentifier
        let runningConflicts = NSWorkspace.shared.runningApplications.compactMap { app -> String? in
            guard let bundleIdentifier = app.bundleIdentifier else { return nil }
            guard bundleIdentifier != ownBundleIdentifier else { return nil }
            guard !app.isTerminated else { return nil }
            return conflictingApps[bundleIdentifier]
        }

        let uniqueConflicts = Array(Set(runningConflicts)).sorted()
        guard !uniqueConflicts.isEmpty else { return }

        let previousPolicy = NSApp.activationPolicy()
        NSApp.setActivationPolicy(.regular)
        if #available(macOS 14, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }

        let appList = uniqueConflicts.joined(separator: ", ")
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Conflicting Menu Bar Manager Detected".localized
        alert.informativeText = String(
            format: "The following menu bar manager is already running: %@. Running multiple menu bar managers at the same time can cause layout issues and unexpected behavior.".localized,
            appList
        )
        alert.addButton(withTitle: "Continue".localized)
        alert.runModal()

        NSApp.setActivationPolicy(previousPolicy)
    }

}
