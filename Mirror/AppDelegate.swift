import AppKit
import UserNotifications

class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {

    private var mainWindowController: FullWindowController?
    private var statusItem: NSStatusItem?
    private var workflowsSubmenu: NSMenu?
    let workflowEngine = WorkflowEngine()
    private let permissionsManager = PermissionsManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }

        setupMainMenu()
        setupStatusItem()
        showMainWindow()

        if !Settings.hasLaunchedBefore {
            Settings.hasLaunchedBefore = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.checkPermissionsOnFirstLaunch()
            }
        }

        workflowEngine.restoreScheduledWorkflows()
    }

    func applicationWillTerminate(_ notification: Notification) {
        workflowEngine.persistWorkflowStates()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { showMainWindow() }
        return true
    }

    // MARK: - Main Menu

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        appMenuItem.submenu = NSMenu()
        appMenuItem.submenu?.addItem(NSMenuItem(title: "About Mirror", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: ""))
        appMenuItem.submenu?.addItem(.separator())
        appMenuItem.submenu?.addItem(NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ","))
        appMenuItem.submenu?.addItem(.separator())
        appMenuItem.submenu?.addItem(NSMenuItem(title: "Hide Mirror", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"))
        appMenuItem.submenu?.addItem(NSMenuItem(title: "Quit Mirror", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        mainMenu.addItem(appMenuItem)

        let fileMenuItem = NSMenuItem()
        fileMenuItem.submenu = NSMenu(title: "File")
        let newRecordingItem = NSMenuItem(title: "New Recording", action: #selector(newRecording), keyEquivalent: "r")
        newRecordingItem.keyEquivalentModifierMask = [.command]
        fileMenuItem.submenu?.addItem(newRecordingItem)
        fileMenuItem.submenu?.addItem(.separator())
        fileMenuItem.submenu?.addItem(NSMenuItem(title: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        mainMenu.addItem(fileMenuItem)

        NSApp.mainMenu = mainMenu
    }

    // MARK: - Status Item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "record.circle", accessibilityDescription: "Mirror")
            button.toolTip = "Mirror"
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Open Mirror", action: #selector(openMainWindow), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "New Recording", action: #selector(newRecording), keyEquivalent: ""))
        menu.addItem(.separator())

        let workflowsItem = NSMenuItem(title: "Workflows", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        workflowsSubmenu = submenu
        refreshMenuBarWorkflows()
        workflowsItem.submenu = submenu
        menu.addItem(workflowsItem)
        menu.addItem(.separator())

        menu.addItem(NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Mirror", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusItem?.menu = menu
    }

    func updateMenuBarRecordingState(_ recording: Bool) {
        DispatchQueue.main.async {
            let name = recording ? "record.circle.fill" : "record.circle"
            self.statusItem?.button?.image = NSImage(systemSymbolName: name, accessibilityDescription: "Mirror")
        }
    }

    func refreshMenuBarWorkflows() {
        guard let submenu = workflowsSubmenu else { return }
        submenu.removeAllItems()
        let workflows = workflowEngine.listWorkflows()
        if workflows.isEmpty {
            let emptyItem = NSMenuItem(title: "No workflows yet", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            submenu.addItem(emptyItem)
        } else {
            for wf in workflows {
                let title = "\(wf.enabled ? "" : "(paused) ")\(wf.name)"
                let item = NSMenuItem(title: title, action: #selector(menuBarRunWorkflow(_:)), keyEquivalent: "")
                item.representedObject = wf.id
                item.target = self
                submenu.addItem(item)
            }
        }
    }

    @objc private func menuBarRunWorkflow(_ sender: NSMenuItem) {
        guard let workflowId = sender.representedObject as? String else { return }
        workflowEngine.executeWorkflow(workflowId: workflowId)
    }

    @objc private func openMainWindow() {
        showMainWindow()
    }

    @objc private func newRecording() {
        showMainWindow()
        mainWindowController?.bridgeCall(name: "menuBarStartRecording", payload: nil)
    }

    // MARK: - Windows

    func showMainWindow() {
        if mainWindowController == nil || mainWindowController?.window == nil {
            let wc = FullWindowController()
            wc.workflowEngine = workflowEngine
            mainWindowController = wc
        }
        mainWindowController?.window?.orderFrontRegardless()
        mainWindowController?.showWindow(nil)
        mainWindowController?.window?.makeKey()
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func openSettings() {
        if mainWindowController == nil {
            showMainWindow()
        }
        mainWindowController?.openSettingsWindow()
    }

    // MARK: - Permissions

    private func checkPermissionsOnFirstLaunch() {
        let screenOK = permissionsManager.hasScreenRecordingPermission()
        let accessOK = permissionsManager.hasAccessibilityPermission()
        if !screenOK || !accessOK {
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Permissions Required"
                alert.informativeText = "Mirror needs Screen Recording and Accessibility permissions to capture your workflows. Open Settings to grant them."
                alert.addButton(withTitle: "Open Settings")
                alert.addButton(withTitle: "Later")
                if alert.runModal() == .alertFirstButtonReturn {
                    self.openSettings()
                }
            }
        }
    }

    // MARK: - Notifications

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        showMainWindow()
        completionHandler()
    }
}