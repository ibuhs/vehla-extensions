import Foundation
import os.log

public enum PSLog {
    public static let app = OSLog(subsystem: "com.kailalabs.vehla.puresnitch", category: "app")
    public static let helper = OSLog(subsystem: "com.kailalabs.vehla.puresnitch", category: "helper")
    public static let dns = OSLog(subsystem: "com.kailalabs.vehla.puresnitch", category: "dns")
    public static let pf = OSLog(subsystem: "com.kailalabs.vehla.puresnitch", category: "pf")
    public static let netmon = OSLog(subsystem: "com.kailalabs.vehla.puresnitch", category: "netmon")

    public static func info(_ log: OSLog, _ msg: String) { os_log("%{public}@", log: log, type: .info, msg) }
    public static func error(_ log: OSLog, _ msg: String) { os_log("%{public}@", log: log, type: .error, msg) }
    public static func debug(_ log: OSLog, _ msg: String) { os_log("%{public}@", log: log, type: .debug, msg) }
}
