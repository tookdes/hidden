//
//  Util.swift
//  vanillaClone
//
//  Created by Thanh Nguyen on 1/29/19.
//  Copyright © 2019 Dwarves Foundation. All rights reserved.
//

import AppKit
import Foundation
import ServiceManagement


class Util {

    static func setUpAutoStart(isAutoStart: Bool) {
        let runningApps = NSWorkspace.shared.runningApplications
        let isRunning = runningApps.contains { $0.bundleIdentifier == Constant.launcherAppId }

        if #available(macOS 13, *) {
            let service = SMAppService.loginItem(identifier: Constant.launcherAppId)
            do {
                if isAutoStart {
                    try service.register()
                } else {
                    try service.unregister()
                }
            } catch {
                // Fall back to legacy API if SMAppService fails
                SMLoginItemSetEnabled(Constant.launcherAppId as CFString, isAutoStart)
            }
        } else {
            SMLoginItemSetEnabled(Constant.launcherAppId as CFString, isAutoStart)
        }

        if isRunning, let bundleId = Bundle.main.bundleIdentifier {
            DistributedNotificationCenter.default().post(name: Notification.Name("killLauncher"),
                                                         object: bundleId)
        }
    }
    
    static func showPrefWindow() {
        let prefWindow = PreferencesWindowController.shared.window
        prefWindow?.bringToFront()
    }
   
}
