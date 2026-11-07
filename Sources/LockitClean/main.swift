// LockitClean — lock your Mac's keyboard & trackpad so you can wipe it clean.
// Unlock: hold BOTH ⌘ keys for 2 seconds, or wait for the timer to run out.

import Cocoa
import ApplicationServices

let unlockHoldSeconds: TimeInterval = 2.0
let durations: [(label: String, seconds: Int)] = [("30 sec", 30), ("1 min", 60), ("2 min", 120), ("5 min", 300)]

// MARK: - Input blocker (CGEventTap)

/// C-style callback for the event tap. Runs on the main run loop.
private func tapCallback(proxy: CGEventTapProxy, type: CGEventType,
                         event: CGEvent, refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    MainActor.assumeIsolated {
        Locker.shared.handle(type: type, event: event)
    }
    return nil // swallow every event — nothing reaches the system while locked
}

@MainActor
final class Locker {
    static let shared = Locker()

    var onHoldChanged: ((Bool) -> Void)?
    var onUnlockCombo: (() -> Void)?

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var holdTimer: Timer?

    // Device-dependent modifier bits (IOKit NX_DEVICELCMDKEYMASK / NX_DEVICERCMDKEYMASK)
    private let leftCmdBit: UInt64 = 0x08
    private let rightCmdBit: UInt64 = 0x10

    static func hasPermission(prompt: Bool) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: prompt] as CFDictionary)
    }

    /// Starts swallowing all keyboard, mouse, trackpad and media-key events.
    func start() -> Bool {
        guard tap == nil else { return true }
        guard let newTap = CGEvent.tapCreate(tap: .cghidEventTap,
                                             place: .headInsertEventTap,
                                             options: .defaultTap,
                                             eventsOfInterest: ~CGEventMask(0), // all events
                                             callback: tapCallback,
                                             userInfo: nil) else { return false }
        tap = newTap
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, newTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: newTap, enable: true)
        return true
    }

    func stop() {
        holdTimer?.invalidate()
        holdTimer = nil
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
    }

    func handle(type: CGEventType, event: CGEvent) {
        // macOS turns a tap off if it's too slow — just turn it back on.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return
        }
        guard type == .flagsChanged else { return }
        let flags = event.flags.rawValue
        let bothCmdDown = (flags & leftCmdBit != 0) && (flags & rightCmdBit != 0)

        if bothCmdDown {
            guard holdTimer == nil else { return }
            onHoldChanged?(true)
            holdTimer = Timer.scheduledTimer(withTimeInterval: unlockHoldSeconds, repeats: false) { _ in
                MainActor.assumeIsolated {
                    Locker.shared.holdTimer = nil
                    Locker.shared.onUnlockCombo?()
                }
            }
        } else if holdTimer != nil {
            holdTimer?.invalidate()
            holdTimer = nil
            onHoldChanged?(false)
        }
    }
}

// MARK: - App

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var startWindow: NSWindow!
    private var statusLabel: NSTextField!
    private var durationPicker: NSSegmentedControl!

    private var lockWindows: [NSWindow] = []
    private var countdownLabel: NSTextField?
    private var hintLabel: NSTextField?
    private var countdownTimer: Timer?
    private var secondsLeft = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()
        buildStartWindow()
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    // MARK: Start window

    private func buildStartWindow() {
        startWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 260),
                               styleMask: [.titled, .closable, .miniaturizable],
                               backing: .buffered, defer: false)
        startWindow.title = "LockitClean"
        startWindow.isReleasedWhenClosed = false

        let icon = label("🧽", size: 48)
        let title = label("Time to clean your Mac", size: 20, weight: .semibold)
        let info = label("Keyboard and trackpad will be locked.\nHold both ⌘ keys for 2 seconds to unlock early.",
                         size: 12, color: .secondaryLabelColor)
        info.alignment = .center

        durationPicker = NSSegmentedControl(labels: durations.map { $0.label },
                                            trackingMode: .selectOne, target: nil, action: nil)
        durationPicker.selectedSegment = 1

        let startButton = NSButton(title: "Lock & Clean", target: self, action: #selector(startPressed))
        startButton.bezelStyle = .rounded
        startButton.keyEquivalent = "\r"
        startButton.controlSize = .large

        statusLabel = label("", size: 12, color: .systemGreen)

        let stack = NSStackView(views: [icon, title, info, durationPicker, startButton, statusLabel])
        stack.orientation = .vertical
        stack.spacing = 12
        stack.setCustomSpacing(4, after: icon)
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        startWindow.contentView = stack
        startWindow.center()
        startWindow.makeKeyAndOrderFront(nil)
    }

    @objc private func startPressed() {
        guard Locker.hasPermission(prompt: true) else {
            let alert = NSAlert()
            alert.messageText = "LockitClean needs Accessibility access"
            alert.informativeText = "To block the keyboard and trackpad, open System Settings → Privacy & Security → Accessibility, turn on LockitClean, then press Lock & Clean again."
            alert.addButton(withTitle: "Open Settings")
            alert.addButton(withTitle: "Cancel")
            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
            }
            return
        }
        lock(seconds: durations[max(durationPicker.selectedSegment, 0)].seconds)
    }

    // MARK: Lock / unlock

    private func lock(seconds: Int) {
        let locker = Locker.shared
        locker.onUnlockCombo = { [weak self] in self?.unlock(message: "Unlocked ✨ Sparkling clean!") }
        locker.onHoldChanged = { [weak self] holding in
            self?.hintLabel?.stringValue = holding ? "Unlocking… keep holding" : self?.defaultHint ?? ""
            self?.hintLabel?.textColor = holding ? .systemGreen : NSColor(white: 1, alpha: 0.6)
        }
        guard locker.start() else {
            statusLabel.textColor = .systemRed
            statusLabel.stringValue = "Couldn't lock input. Check Accessibility permission."
            return
        }

        startWindow.orderOut(nil)
        showLockWindows()
        NSCursor.hide()
        NSApp.presentationOptions = [.hideDock, .hideMenuBar, .disableProcessSwitching,
                                     .disableForceQuit, .disableSessionTermination, .disableHideApplication]

        secondsLeft = seconds
        updateCountdown()
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    private func tick() {
        secondsLeft -= 1
        if secondsLeft <= 0 {
            unlock(message: "Time's up — unlocked ✨")
        } else {
            updateCountdown()
        }
    }

    private func unlock(message: String) {
        countdownTimer?.invalidate()
        countdownTimer = nil
        Locker.shared.stop()
        NSApp.presentationOptions = []
        NSCursor.unhide()
        lockWindows.forEach { $0.orderOut(nil) }
        lockWindows.removeAll()
        countdownLabel = nil
        hintLabel = nil

        statusLabel.textColor = .systemGreen
        statusLabel.stringValue = message
        startWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private var defaultHint: String { "Hold both ⌘ keys for 2 seconds to unlock" }

    private func updateCountdown() {
        countdownLabel?.stringValue = String(format: "%d:%02d", secondsLeft / 60, secondsLeft % 60)
    }

    private func showLockWindows() {
        for screen in NSScreen.screens {
            let window = NSWindow(contentRect: screen.frame, styleMask: .borderless,
                                  backing: .buffered, defer: false, screen: screen)
            window.level = .screenSaver
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            window.backgroundColor = NSColor(calibratedRed: 0.05, green: 0.07, blue: 0.12, alpha: 1)
            window.isOpaque = true
            window.isReleasedWhenClosed = false

            var views: [NSView] = [label("🧽", size: 90), label("Cleaning mode", size: 44, weight: .bold, color: .white)]
            if screen == NSScreen.main || NSScreen.screens.count == 1 {
                let countdown = label("", size: 30, weight: .medium, color: NSColor(white: 1, alpha: 0.85))
                countdown.font = .monospacedDigitSystemFont(ofSize: 30, weight: .medium)
                let hint = label(defaultHint, size: 15, color: NSColor(white: 1, alpha: 0.6))
                countdownLabel = countdown
                hintLabel = hint
                views += [countdown, hint]
            }

            let stack = NSStackView(views: views)
            stack.orientation = .vertical
            stack.spacing = 14
            stack.translatesAutoresizingMaskIntoConstraints = false
            let container = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
            container.addSubview(stack)
            NSLayoutConstraint.activate([
                stack.centerXAnchor.constraint(equalTo: container.centerXAnchor),
                stack.centerYAnchor.constraint(equalTo: container.centerYAnchor)
            ])
            window.contentView = container
            window.setFrame(screen.frame, display: true)
            window.orderFrontRegardless()
            lockWindows.append(window)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: Helpers

    private func label(_ text: String, size: CGFloat, weight: NSFont.Weight = .regular,
                       color: NSColor = .labelColor) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = .systemFont(ofSize: size, weight: weight)
        field.textColor = color
        field.alignment = .center
        return field
    }

    private func buildMenu() {
        let mainMenu = NSMenu()
        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit LockitClean", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        NSApp.mainMenu = mainMenu
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.regular)
    app.run()
}
