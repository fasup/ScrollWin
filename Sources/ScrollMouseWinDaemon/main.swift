@preconcurrency import ApplicationServices
import CoreGraphics
import Foundation

func log(_ msg: String) {
    let line = msg + "\n"
    if let fh = FileHandle(forWritingAtPath: "/tmp/scrollwin_daemon.log") {
        fh.seekToEndOfFile(); fh.write(line.data(using: .utf8)!)
    } else {
        FileManager.default.createFile(atPath: "/tmp/scrollwin_daemon.log", contents: line.data(using: .utf8))
    }
}

log("daemon started, PID=\(ProcessInfo.processInfo.processIdentifier)")

// Re-enable the tap after a system-imposed timeout.
var gTap: CFMachPort?

func waitForAccessibilityPermission() {
    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
    let initialTrusted = AXIsProcessTrustedWithOptions(options)
    log("AXIsProcessTrustedWithOptions: \(initialTrusted)")

    guard !initialTrusted else { return }

    fputs("scrollwin-daemon: waiting for Accessibility permission\n", stderr)
    log("waiting for Accessibility permission")

    while !AXIsProcessTrusted() {
        Thread.sleep(forTimeInterval: 2.0)
    }

    log("Accessibility permission granted")
}

waitForAccessibilityPermission()

let mask = CGEventMask(1 << CGEventType.scrollWheel.rawValue)

func shouldInvertScrollEvent(_ event: CGEvent) -> Bool {
    let isContinuous = event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0
    if !isContinuous { return true }

    // Trackpads and momentum scrolling usually carry explicit phases.
    // Some physical mice emit "continuous" wheel events but keep both phases at 0.
    let phase = event.getIntegerValueField(.scrollWheelEventScrollPhase)
    let momentumPhase = event.getIntegerValueField(.scrollWheelEventMomentumPhase)
    return phase == 0 && momentumPhase == 0
}

log("creating CGEventTap...")
guard let tap = CGEvent.tapCreate(
    tap: .cgSessionEventTap,
    place: .headInsertEventTap,
    options: .defaultTap,
    eventsOfInterest: mask,
    callback: { _, type, event, _ in
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let t = gTap { CGEvent.tapEnable(tap: t, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard type == .scrollWheel else { return Unmanaged.passUnretained(event) }

        guard shouldInvertScrollEvent(event) else {
            return Unmanaged.passUnretained(event)
        }

        let d1 = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
        let p1 = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)
        let f1 = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
        log("invert scroll: continuous=\(event.getIntegerValueField(.scrollWheelEventIsContinuous)) phase=\(event.getIntegerValueField(.scrollWheelEventScrollPhase)) momentum=\(event.getIntegerValueField(.scrollWheelEventMomentumPhase)) d1=\(d1) p1=\(p1)")
        event.setIntegerValueField(.scrollWheelEventDeltaAxis1,      value: -d1)
        event.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: -p1)
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: -f1)

        return Unmanaged.passUnretained(event)
    },
    userInfo: nil
) else {
    log("FAILED to create CGEventTap")
    fputs("scrollwin-daemon: failed to create CGEventTap\n", stderr)
    exit(1)
}

log("CGEventTap OK — running")
gTap = tap
let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
CGEvent.tapEnable(tap: tap, enable: true)
CFRunLoopRun()
