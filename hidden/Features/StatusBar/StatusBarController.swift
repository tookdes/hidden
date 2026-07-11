//
//  StatusBarController.swift
//  vanillaClone
//
//  Created by Thanh Nguyen on 1/30/19.
//  Copyright © 2019 Dwarves Foundation. All rights reserved.
//

import AppKit

class StatusBarController {
    
    //MARK: - Variables
    private var timer:Timer? = nil
    
    //MARK: - BarItems
        
    private let btnExpandCollapse = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let btnSeparate = NSStatusBar.system.statusItem(withLength: 1)
    private var btnAlwaysHidden:NSStatusItem? = nil
    
    private var btnHiddenLength: CGFloat = 20
    private var btnHiddenCollapseLength: CGFloat = 2000
    
    private var btnAlwaysHiddenLength: CGFloat = Preferences.alwaysHiddenSectionEnabled ? 20 : 0
    private var btnAlwaysHiddenEnableExpandCollapseLength: CGFloat = Preferences.alwaysHiddenSectionEnabled ? 2000 : 0
    
    private let imgIconLine = NSImage(named:NSImage.Name("ic_line"))
    
    private var isCollapsed: Bool {
        // Compare with > rather than == so the state survives updateCollapsedLengths
        // changing btnHiddenCollapseLength while the bar is collapsed (PR #354).
        return self.btnSeparate.length > self.btnHiddenLength
    }
    
    private var isBtnSeparateValidPosition: Bool {
        guard
            let btnExpandCollapseX = self.btnExpandCollapse.button?.getOrigin?.x,
            let btnSeparateX = self.btnSeparate.button?.getOrigin?.x
            else {return false}
        
        if Constant.isUsingLTRLanguage {
            return btnExpandCollapseX >= btnSeparateX
        } else {
            return btnExpandCollapseX <= btnSeparateX
        }
    }
    
    private var isBtnAlwaysHiddenValidPosition: Bool {
        if !Preferences.alwaysHiddenSectionEnabled { return true }
        
        guard
            let btnSeparateX = self.btnSeparate.button?.getOrigin?.x,
            let btnAlwaysHiddenX = self.btnAlwaysHidden?.button?.getOrigin?.x
            else {return false}
        
        if Constant.isUsingLTRLanguage {
            return btnSeparateX >= btnAlwaysHiddenX
        } else {
            return btnSeparateX <= btnAlwaysHiddenX
        }
    }
    
    private var isToggle = false

    // SPEC-003 (macOS 27 hide-mechanism). macOS 27 re-architected the menu bar so
    // inflating the separator length may no longer push items off-screen (#360).
    // This is DIAGNOSTIC ONLY: on the first collapse with the menu-bar window
    // ready, log the separator geometry so a macOS 27 run reveals which signal
    // (if any) distinguishes "length honored" from "ignored". No behavior change.
    // The degrade ACTION is deliberately NOT shipped: review found the trigger
    // unverifiable without 27 hardware, and a false positive would disable hiding
    // for a working user. The action lands once this log calibrates the signal.
    private var hideMechanismChecked = false

    private var hoverMonitor: Any?
    private var hoverDwellTimer: Timer?

    // Fork-unique: notch-aware popover listing off-screen status items, plus a
    // single collapse retry when Cmd-drag rearranges icons mid-collapse.
    private var notchPopover: NSPopover?
    private var cachedNotchItems: [HiddenMenuBarItem]?
    private var notchCacheTime: Date?
    private let notchPopoverDelegate = NotchPopoverDelegate()
    private var collapseRetryCount = 0
    private var collapseRetryWorkItem: DispatchWorkItem?

    // True while the pointer sits in any screen's menubar band (the strip between
    // visibleFrame.maxY and frame.maxY, which is the menubar's exact height there).
    // On fullscreen spaces the menubar is hidden and the band collapses to ~zero,
    // so this returns false there: intentional, no visible menubar = no deferral.
    private var isMouseInMenuBar: Bool {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.contains { screen in
            mouse.x >= screen.frame.minX && mouse.x <= screen.frame.maxX
                && mouse.y >= screen.visibleFrame.maxY && mouse.y <= screen.frame.maxY
        }
    }

    // The preferences window is an ordinary app window, not in the menu bar, so
    // the mouse-in-menubar guard does not cover it. With "use full menu bar on
    // expanding" on, an auto-collapse deactivates the app and dismisses this
    // window mid-edit (#170, same family as #66/#151). Defer the collapse while
    // it is on screen. isWindowLoaded short-circuits without force-loading the
    // window when preferences were never opened.
    private var isPreferencesWindowVisible: Bool {
        let wc = PreferencesWindowController.shared
        return wc.isWindowLoaded && (wc.window?.isVisible ?? false)
    }
    
    //MARK: - Methods
    init() {
        updateCollapsedLengths()
        setupUI()
        restoreRemovedStatusItems()
        setupAlwayHideStatusBar()
        setupHoverToExpandIfEnabled()
        notchPopoverDelegate.onClose = { [weak self] in
            self?.notchPopover = nil
        }
        NotificationCenter.default.addObserver(self, selector: #selector(handleScreenParametersChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.collapseMenuBar()
        }
        
        if Preferences.areSeparatorsHidden {hideSeparators()}
        autoCollapseIfNeeded()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        timer?.invalidate()
        hoverDwellTimer?.invalidate()
        notchPopover?.close()
        collapseRetryWorkItem?.cancel()
        if let monitor = hoverMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    // Opt-in via `defaults write com.dwarvesv.minimalbar hoverToExpand -bool true`.
    // No monitor is installed at all unless the pref is true at launch.
    private func setupHoverToExpandIfEnabled() {
        guard Preferences.hoverToExpand else { return }
        NSLog("HoverToExpand: enabled, installing global mouse monitor")
        hoverMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
            guard let self = self else { return }
            guard self.isCollapsed && self.isMouseInMenuBar else {
                self.hoverDwellTimer?.invalidate()
                self.hoverDwellTimer = nil
                return
            }
            // Short dwell so a pointer merely passing through doesn't expand.
            guard self.hoverDwellTimer == nil else { return }
            self.hoverDwellTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
                guard let self = self else { return }
                self.hoverDwellTimer = nil
                if self.isCollapsed && self.isMouseInMenuBar {
                    if self.showNotchPopoverIfNeeded() {
                        return
                    }
                    self.expandMenubar()
                }
            }
        }
    }
    
    @objc private func handleScreenParametersChanged() {
        // Re-apply the recomputed length to the LIVE item when collapsed, or a
        // display hot-plug leaves the separator at a stale length (PR #354).
        let wasCollapsed = isCollapsed
        updateCollapsedLengths()
        invalidateNotchItemsCache()
        if wasCollapsed {
            btnSeparate.length = btnHiddenCollapseLength
            if Preferences.areSeparatorsHidden {
                btnAlwaysHidden?.length = btnAlwaysHiddenEnableExpandCollapseLength
            }
        }
    }

    private func updateCollapsedLengths() {
        // The menubar replicates across every attached display, so the collapse
        // length must cover the WIDEST screen, not NSScreen.main (the focused one);
        // sizing from a narrower screen leaks hidden icons on wider displays.
        // frame.width, not visibleFrame: the menubar spans the full frame width.
        let screenWidth = NSScreen.screens.map { $0.frame.width }.max() ?? 1728
        // Keep collapse length bounded to avoid pathological layout/memory behavior;
        // macOS enforces a hard 10,000pt maximum on NSStatusItem.length (PR #354).
        let boundedCollapseLength = max(500, min(screenWidth * 2, 10_000))
        btnHiddenCollapseLength = boundedCollapseLength
        btnAlwaysHiddenEnableExpandCollapseLength = Preferences.alwaysHiddenSectionEnabled ? boundedCollapseLength : 0
    }
    
    private func restoreRemovedStatusItems() {
        // Cmd-dragging a status item off the bar is persisted by macOS via
        // autosaveName, leaving the app running but unreachable. These items are
        // the app's only UI, so they self-restore at launch.
        btnExpandCollapse.isVisible = true
        btnSeparate.isVisible = true
    }

    private func setupUI() {
        if let button = btnSeparate.button {
            button.image = self.imgIconLine
        }
        let menu = self.getContextMenu()
        btnSeparate.menu = menu

        updateAutoCollapseMenuTitle()
        
        if let button = btnExpandCollapse.button {
            button.image = Assets.collapseImage
            button.target = self
            
            button.action = #selector(self.btnExpandCollapsePressed(sender:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        
        btnExpandCollapse.autosaveName = "hiddenbar_expandcollapse";
        btnSeparate.autosaveName = "hiddenbar_separate";
    }
    
    @objc func btnExpandCollapsePressed(sender: NSStatusBarButton) {
        if let event = NSApp.currentEvent {

            let isOptionKeyPressed = event.modifierFlags.contains(NSEvent.ModifierFlags.option)

            if event.type == NSEvent.EventType.leftMouseUp && !isOptionKeyPressed{
                if showNotchPopoverIfNeeded() {
                    return
                }
                self.expandCollapseIfNeeded()
            } else if event.type == NSEvent.EventType.rightMouseUp && !isOptionKeyPressed {
                // Right-click opens the same context menu the separator has (#356),
                // making settings reachable from the control everyone clicks.
                // The separators/always-hidden toggle stays on option-click.
                showContextMenu(from: sender)
            } else {
                // Both option+left and option+right land here: separators toggle.
                self.showHideSeparatorsAndAlwayHideArea()
            }
        }
    }

    private func showContextMenu(from button: NSStatusBarButton) {
        guard let menu = btnSeparate.menu else { return }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.maxY + 5), in: button)
    }
    
    func showHideSeparatorsAndAlwayHideArea() {
        Preferences.areSeparatorsHidden ? self.showSeparators() : self.hideSeparators()
        
        if self.isCollapsed {self.expandMenubar()}
    }
    
    private func showSeparators() {
        Preferences.areSeparatorsHidden = false
        
        if !self.isCollapsed {
            self.btnSeparate.length = self.btnHiddenLength
        }
        self.btnAlwaysHidden?.length = self.btnAlwaysHiddenLength
    }
    
    private func hideSeparators() {
        guard self.isBtnAlwaysHiddenValidPosition else {return}
        
        Preferences.areSeparatorsHidden = true
        
        if !self.isCollapsed {
            self.btnSeparate.length = self.btnHiddenLength
        }
        self.btnAlwaysHidden?.length = self.btnAlwaysHiddenEnableExpandCollapseLength
    }
    
    func expandCollapseIfNeeded() {
        //prevented rapid click cause icon show many in Dock
        if isToggle {return}
        isToggle = true
        self.isCollapsed ? self.expandMenubar() : self.collapseMenuBar()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.isToggle = false
        }
    }
    
    private func collapseMenuBar() {
        guard !self.isCollapsed else {
            return
        }

        invalidateNotchItemsCache()

        // Allow one retry if position validation fails (e.g., user Cmd-dragged icons)
        if !self.isBtnSeparateValidPosition {
            if collapseRetryCount < 1 {
                collapseRetryCount += 1
                scheduleCollapseRetry()
                return
            }
            // Retry exhausted — force collapse anyway so auto-hide cannot get stuck.
        }
        collapseRetryCount = 0

        btnSeparate.length = self.btnHiddenCollapseLength
        if let button = btnExpandCollapse.button {
            button.image = Assets.expandImage
        }
        if Preferences.useFullStatusBarOnExpandEnabled {
            NSApp.setActivationPolicy(.accessory)
            NSApp.deactivate()
        }
        verifyHideMechanismIfNeeded()
    }

    private func scheduleCollapseRetry() {
        collapseRetryWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.collapseMenuBar()
        }
        collapseRetryWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: workItem)
    }
    private func expandMenubar() {
        guard self.isCollapsed else {return}
        notchPopover?.close()
        invalidateNotchItemsCache()
        collapseRetryWorkItem?.cancel()
        collapseRetryCount = 0
        btnSeparate.length = btnHiddenLength
        if let button = btnExpandCollapse.button {
            button.image = Assets.collapseImage
        }
        autoCollapseIfNeeded()

        if Preferences.useFullStatusBarOnExpandEnabled {
            NSApp.setActivationPolicy(.regular)
            if #available(macOS 14, *) {
                NSApp.activate()
            } else {
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }
    
    private func autoCollapseIfNeeded() {
        guard Preferences.isAutoHide else {
            timer?.invalidate()
            timer = nil
            return
        }
        guard !isCollapsed else { return }

        startTimerToAutoHide()
    }

    // After a collapse, confirm on the next runloop tick (so layout settles) that
    // the separator actually claimed its inflated width. macOS <= 26 honors it;
    // a macOS that ignores NSStatusItem.length leaves the slot narrow, meaning
    // hiding did nothing. Checked once: cheap, and the OS behavior won't change
    // mid-session.
    private func verifyHideMechanismIfNeeded() {
        guard !hideMechanismChecked else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.isCollapsed else { return }
            // Need the separator's backing window to measure. If it is not up yet
            // (early launch), do NOT burn the one-shot check: return and let a
            // later collapse retry once the window exists.
            guard let separatorButton = self.btnSeparate.button,
                  let window = separatorButton.window else { return }
            self.hideMechanismChecked = true
            // Log several geometry signals. On macOS <= 26 the inflation is
            // honored; on macOS 27 it may be ignored. Which of these tracks the
            // requested length is exactly what a 27 capture must reveal before any
            // degrade action can trigger on a sound signal.
            let requested = self.btnHiddenCollapseLength
            let windowWidth = window.frame.width
            let buttonWidth = separatorButton.frame.width
            NSLog("HideMechanism: requested=\(requested) windowWidth=\(windowWidth) buttonWidth=\(buttonWidth) length=\(self.btnSeparate.length)")
        }
    }
    
    private func startTimerToAutoHide() {
        timer?.invalidate()
        self.timer = Timer.scheduledTimer(withTimeInterval: Preferences.numberOfSecondForAutoHide, repeats: false) { [weak self] _ in
            guard let self = self, Preferences.isAutoHide else { return }
            // Don't yank the bar shut mid-interaction: while the pointer is in the
            // menubar (hovering, clicking, dragging icons), defer and re-arm.
            // Intentionally unbounded; each re-arm invalidates the previous timer,
            // so deferral never accumulates timers.
            if self.isMouseInMenuBar || self.isPreferencesWindowVisible {
                self.startTimerToAutoHide()
            } else {
                self.collapseMenuBar()
            }
        }
    }
    
    private func getContextMenu() -> NSMenu {
        let menu = NSMenu()
        
        let prefItem = NSMenuItem(title: "Preferences...".localized, action: #selector(openPreferenceViewControllerIfNeeded), keyEquivalent: "P")
        prefItem.target = self
        menu.addItem(prefItem)
        
        let toggleAutoHideItem = NSMenuItem(title: "Toggle Auto Collapse".localized, action: #selector(toggleAutoHide), keyEquivalent: "t")
        toggleAutoHideItem.target = self
        toggleAutoHideItem.tag = 1
        NotificationCenter.default.addObserver(self, selector: #selector(updateAutoHide), name: .prefsChanged, object: nil)
        menu.addItem(toggleAutoHideItem)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit".localized, action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        
        return menu
    }
    
    private func updateAutoCollapseMenuTitle() {
        guard let toggleAutoHideItem = btnSeparate.menu?.item(withTag: 1) else { return }
        if Preferences.isAutoHide {
            toggleAutoHideItem.title = "Disable Auto Collapse".localized
        } else {
            toggleAutoHideItem.title = "Enable Auto Collapse".localized
        }
    }
    
    @objc func updateAutoHide() {
        updateAutoCollapseMenuTitle()
        autoCollapseIfNeeded()
    }
    
    @objc func openPreferenceViewControllerIfNeeded() {
        Util.showPrefWindow()
    }
    
    @objc func toggleAutoHide() {
        Preferences.isAutoHide.toggle()
    }
}

// MARK: - Notch popover (fork)
extension StatusBarController {
    private func showNotchPopoverIfNeeded() -> Bool {
        guard isCollapsed, isMainScreenNotched() else { return false }
        guard let button = btnExpandCollapse.button else { return false }

        let hiddenItems = hiddenMenuBarItemsForNotchPopover()
        guard !hiddenItems.isEmpty else { return false }

        if notchPopover?.isShown == true {
            notchPopover?.close()
            return true
        }

        let controller = HiddenMenuBarItemsViewController(items: hiddenItems)
        let popover = NSPopover()
        popover.contentViewController = controller
        popover.contentSize = controller.preferredContentSize
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = notchPopoverDelegate
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        notchPopover = popover
        return true
    }

    private func isMainScreenNotched() -> Bool {
        return (NSScreen.main?.safeAreaInsets.top ?? 0) >= 24
    }

    private func hiddenMenuBarItemsForNotchPopover() -> [HiddenMenuBarItem] {
        if let cachedNotchItems = cachedNotchItems,
           let notchCacheTime = notchCacheTime,
           Date().timeIntervalSince(notchCacheTime) < 0.5 {
            return cachedNotchItems
        }

        guard let screen = NSScreen.main else { return [] }
        // Hidden status item windows are usually marked off-screen after the
        // separator pushes them past the display edge, so .optionOnScreenOnly
        // misses the items this popover needs to list.
        let options: CGWindowListOption = [.optionAll]
        guard let windowInfoList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[CFString: Any]] else {
            return []
        }

        let ownPID = ProcessInfo.processInfo.processIdentifier
        let statusWindowLevel = CGWindowLevelForKey(.statusWindow)
        let screenFrame = screen.frame
        let menuBarHeight = max(NSStatusBar.system.thickness, screenFrame.height - screen.visibleFrame.height)
        let menuBarMinY = screenFrame.maxY - menuBarHeight - 4
        let menuBarMaxY = screenFrame.maxY + 2

        var seenPIDs = Set<pid_t>()
        let items = windowInfoList.compactMap { info -> HiddenMenuBarItem? in
            guard let ownerPID = info[kCGWindowOwnerPID] as? pid_t, ownerPID != ownPID else { return nil }
            guard !seenPIDs.contains(ownerPID) else { return nil }
            guard let layer = info[kCGWindowLayer] as? Int, CGWindowLevel(Int32(layer)) == statusWindowLevel else { return nil }
            guard let boundsDictionary = info[kCGWindowBounds] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDictionary)
            else { return nil }
            guard isOutsideScreenHorizontally(bounds, screenFrame: screenFrame) else { return nil }
            guard bounds.height > 0, bounds.height <= menuBarHeight + 4 else { return nil }
            // CGWindow bounds use top-left origin; menubar sits near the top edge.
            guard bounds.midY >= menuBarMinY, bounds.midY <= menuBarMaxY else { return nil }

            guard let app = NSRunningApplication(processIdentifier: ownerPID) else { return nil }
            seenPIDs.insert(ownerPID)

            let name = app.localizedName ?? info[kCGWindowOwnerName] as? String ?? "Menu Bar Item".localized
            return HiddenMenuBarItem(name: name, icon: app.icon)
        }

        cachedNotchItems = items
        notchCacheTime = Date()
        return items
    }

    private func isOutsideScreenHorizontally(_ bounds: CGRect, screenFrame: CGRect) -> Bool {
        return bounds.maxX <= screenFrame.minX || bounds.minX >= screenFrame.maxX
    }

    private func invalidateNotchItemsCache() {
        cachedNotchItems = nil
        notchCacheTime = nil
    }
}

private struct HiddenMenuBarItem {
    let name: String
    let icon: NSImage?
}

private final class NotchPopoverDelegate: NSObject, NSPopoverDelegate {
    var onClose: (() -> Void)?

    func popoverDidClose(_ notification: Notification) {
        onClose?()
    }
}

private final class HiddenMenuBarItemsViewController: NSViewController {
    private let items: [HiddenMenuBarItem]

    init(items: [HiddenMenuBarItem]) {
        self.items = items
        super.init(nibName: nil, bundle: nil)
        preferredContentSize = CGSize(width: 260, height: min(CGFloat(items.count) * 34 + 42, 282))
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func loadView() {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = items.count > 7
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder

        let contentSize = CGSize(width: 260, height: CGFloat(items.count) * 34 + 42)
        let contentView = NSView(frame: NSRect(origin: .zero, size: contentSize))

        let stackView = NSStackView()
        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = 0
        stackView.edgeInsets = NSEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        stackView.translatesAutoresizingMaskIntoConstraints = false

        for item in items {
            stackView.addArrangedSubview(HiddenMenuBarItemRow(item: item))
        }
        stackView.addArrangedSubview(makeHintTextField())

        contentView.addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            stackView.topAnchor.constraint(equalTo: contentView.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])

        scrollView.documentView = contentView
        view = scrollView
    }

    private func makeHintTextField() -> NSTextField {
        let hint = NSTextField(labelWithString: "Click the arrow to expand".localized)
        hint.font = NSFont.systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        hint.lineBreakMode = .byTruncatingTail
        hint.translatesAutoresizingMaskIntoConstraints = false
        hint.heightAnchor.constraint(equalToConstant: 22).isActive = true
        return hint
    }
}

private final class HiddenMenuBarItemRow: NSView {
    init(item: HiddenMenuBarItem) {
        super.init(frame: .zero)

        let imageView = NSImageView()
        imageView.image = item.icon
        imageView.imageScaling = .scaleProportionallyDown
        imageView.translatesAutoresizingMaskIntoConstraints = false

        let textField = NSTextField(labelWithString: item.name)
        textField.lineBreakMode = .byTruncatingTail
        textField.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textField.translatesAutoresizingMaskIntoConstraints = false

        let stackView = NSStackView(views: [imageView, textField])
        stackView.orientation = .horizontal
        stackView.alignment = .centerY
        stackView.spacing = 8
        stackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stackView)

        NSLayoutConstraint.activate([
            imageView.widthAnchor.constraint(equalToConstant: 20),
            imageView.heightAnchor.constraint(equalToConstant: 20),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stackView.topAnchor.constraint(equalTo: topAnchor, constant: 5),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -5),
            heightAnchor.constraint(equalToConstant: 34),
            widthAnchor.constraint(greaterThanOrEqualToConstant: 220)
        ])
    }

    required init?(coder: NSCoder) {
        return nil
    }
}


//MARK: - Alway hide feature
extension StatusBarController {
    private func setupAlwayHideStatusBar() {
        NotificationCenter.default.addObserver(self, selector: #selector(toggleStatusBarIfNeeded), name: .alwayHideToggle, object: nil)
        toggleStatusBarIfNeeded()
    }
    @objc private func toggleStatusBarIfNeeded() {
        updateCollapsedLengths()

        if Preferences.alwaysHiddenSectionEnabled {
            if let existing = self.btnAlwaysHidden {
                NSStatusBar.system.removeStatusItem(existing)
            }
            self.btnAlwaysHidden = NSStatusBar.system.statusItem(withLength: btnAlwaysHiddenLength)
            if let button = btnAlwaysHidden?.button {
                button.image = self.imgIconLine
                button.appearsDisabled = true
            }
            self.btnAlwaysHidden?.autosaveName = "hiddenbar_terminate"
            self.btnAlwaysHidden?.isVisible = true
        } else {
            if let existing = self.btnAlwaysHidden {
                NSStatusBar.system.removeStatusItem(existing)
            }
            self.btnAlwaysHidden = nil
        }
    }
}
