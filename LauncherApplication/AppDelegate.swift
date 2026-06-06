//
//  AppDelegate.swift
//  LauncherApplication
//
//  Created by Thanh Nguyen on 1/28/19.
//  Copyright © 2019 Dwarves Foundation. All rights reserved.
//

import Cocoa


@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {

    private var mainAppPollingTimer: Timer?

    @objc func terminate() {
        NSApp.terminate(nil)
    }

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        let mainAppIdentifier = "com.dwarvesv.minimalbar"
        let runningApps = NSWorkspace.shared.runningApplications
        let isRunning = runningApps.contains { $0.bundleIdentifier == mainAppIdentifier }

        if !isRunning {
            DistributedNotificationCenter.default().addObserver(self,
                                                                selector: #selector(self.terminate),
                                                                name: Notification.Name("killLauncher"),
                                                                object: mainAppIdentifier)

            let launcherURL = Bundle.main.bundleURL
            let mainAppURL = launcherURL
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()

            guard mainAppURL.pathExtension == "app" else {
                NSLog("Hidden Bar Launcher: Could not derive main app bundle from launcher path: \(launcherURL.path)")
                self.terminate()
                return
            }

            if #available(macOS 10.15, *) {
                let config = NSWorkspace.OpenConfiguration()
                NSWorkspace.shared.openApplication(at: mainAppURL, configuration: config) { [weak self] _, error in
                    if let error = error {
                        NSLog("Hidden Bar Launcher: Failed to launch main app: \(error.localizedDescription)")
                    }
                    DispatchQueue.main.async {
                        self?.terminate()
                    }
                }
            } else {
                let success = NSWorkspace.shared.launchApplication(mainAppURL.path)
                if !success {
                    NSLog("Hidden Bar Launcher: Failed to launch main app at path: \(mainAppURL.path)")
                }
                // Poll for main app in case DistributedNotificationCenter doesn't work across sandbox
                startPollingForMainApp(identifier: mainAppIdentifier)
            }
        }
        else {
            self.terminate()
        }
    }

    private func startPollingForMainApp(identifier: String) {
        mainAppPollingTimer?.invalidate()
        mainAppPollingTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] timer in
            let isRunning = NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == identifier }
            if isRunning {
                timer.invalidate()
                self?.mainAppPollingTimer = nil
                self?.terminate()
            }
        }
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        mainAppPollingTimer?.invalidate()
        DistributedNotificationCenter.default().removeObserver(self)
    }


}
