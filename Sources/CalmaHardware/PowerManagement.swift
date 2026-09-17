import Foundation
import IOKit.pwr_mgt

/// Holds (or releases) a system-sleep assertion. Idempotent.
public final class SleepAssertion {
    private var assertionID: IOPMAssertionID = 0
    private var held = false
    private let name: String

    public init(name: String) {
        self.name = name
    }

    deinit { set(false) }

    public var isHeld: Bool { held }

    /// `PreventSystemSleep` keeps the Mac awake on AC even with the lid closed, while still
    /// letting the display turn off.
    public func set(_ hold: Bool) {
        if hold == held { return }
        if hold {
            var id: IOPMAssertionID = 0
            let result = IOPMAssertionCreateWithName("PreventSystemSleep" as CFString,
                                                     IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                                     name as CFString, &id)
            if result == kIOReturnSuccess {
                assertionID = id
                held = true
            }
        } else {
            IOPMAssertionRelease(assertionID)
            assertionID = 0
            held = false
        }
    }
}

/// Receives system sleep/wake notifications. Must be created on a thread with a run loop (the main thread).
public final class SystemPowerObserver {
    public enum Event { case willSleep, didWake }

    private var rootPort: io_connect_t = 0
    private var notifier: io_object_t = 0
    private var notifyPort: IONotificationPortRef?
    private let handler: (Event) -> Void

    public init(handler: @escaping (Event) -> Void) {
        self.handler = handler
        let context = Unmanaged.passUnretained(self).toOpaque()
        rootPort = IORegisterForSystemPower(context, &notifyPort, { refcon, _, messageType, messageArgument in
            guard let refcon else { return }
            let observer = Unmanaged<SystemPowerObserver>.fromOpaque(refcon).takeUnretainedValue()
            observer.handle(messageType: messageType, argument: messageArgument)
        }, &notifier)
        if let notifyPort {
            CFRunLoopAddSource(CFRunLoopGetMain(), IONotificationPortGetRunLoopSource(notifyPort).takeUnretainedValue(), .commonModes)
        }
    }

    deinit {
        if notifier != 0 { IODeregisterForSystemPower(&notifier) }
        if let notifyPort { IONotificationPortDestroy(notifyPort) }
        if rootPort != 0 { IOServiceClose(rootPort) }
    }

    private func handle(messageType: natural_t, argument: UnsafeMutableRawPointer?) {
        let notificationID = Int(bitPattern: argument)
        switch messageType {
        case UInt32(kIOMessageCanSystemSleep):
            IOAllowPowerChange(rootPort, notificationID)
        case UInt32(kIOMessageSystemWillSleep):
            handler(.willSleep)
            IOAllowPowerChange(rootPort, notificationID)
        case UInt32(kIOMessageSystemHasPoweredOn):
            handler(.didWake)
        default:
            break
        }
    }
}

// IOKit message constants are C macros that don't import into Swift.
private let kIOMessageCanSystemSleep: UInt32 = 0xE000_0270
private let kIOMessageSystemWillSleep: UInt32 = 0xE000_0280
private let kIOMessageSystemHasPoweredOn: UInt32 = 0xE000_0300

/// Mac model and OS details for capability reports.
public enum MachineInfo {
    public static var modelIdentifier: String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        guard size > 0 else { return "unknown" }
        var buffer = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &buffer, &size, nil, 0)
        return String(cString: buffer)
    }

    public static var osVersion: String {
        ProcessInfo.processInfo.operatingSystemVersionString
    }
}
