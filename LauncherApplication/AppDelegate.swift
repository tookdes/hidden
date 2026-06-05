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

    private var hasLaunchedMainApp = false

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

            let path = Bundle.main.bundlePath as NSString
            var components = path.pathComponents
            guard components.count > 3 else {
                NSLog("Hidden Bar Launcher: Bundle path too shallow to derive main app path (\(components.count) components)")
                self.terminate()
                return
            }
            components.removeLast(3)
            components.append("MacOS")
            let appName = "Hidden Bar"
            components.append(appName) //main app name
            let newPath = NSString.path(withComponents: components)

            if #available(macOS 10.15, *) {
                let config = NSWorkspace.OpenConfiguration()
                NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: newPath), configuration: config) { [weak self] _, error in
                    if let error = error {
                        NSLog("Hidden Bar Launcher: Failed to launch main app: \(error.localizedDescription)")
                    }
                    DispatchQueue.main.async {
                        self?.terminate()
                    }
                }
            } else {
                let success = NSWorkspace.shared.launchApplication(newPath)
                if !success {
                    NSLog("Hidden Bar Launcher: Failed to launch main app at path: \(newPath)")
                }
                // Poll for main app in case DistributedNotificationCenter doesn't work across sandbox
                hasLaunchedMainApp = true
                startPollingForMainApp(identifier: mainAppIdentifier)
            }
        }
        else {
            self.terminate()
        }
    }

    private func startPollingForMainApp(identifier: String) {
        Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] timer in
            let isRunning = NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == identifier }
            if isRunning {
                timer.invalidate()
                self?.terminate()
            }
        }
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        DistributedNotificationCenter.default().removeObserver(self)
    }


}
