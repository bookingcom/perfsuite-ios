//
//  ProcessStartTime.swift
//  PerformanceSuite
//
//  Created by Ahmed Nafei on 09/06/2026.
//

import Darwin
import Foundation

/// Reads the wall-clock moment at which the current process started, via
/// sysctl `kern.proc.pid`. Returns seconds since the Unix epoch.
///
/// Shared between ``StartupTimeReporter`` (for startup timing) and the public
/// ``PerformanceMonitoring/processStartTime`` accessor (used as an
/// app-session anchor by downstream consumers).
func readProcessStartTime() -> TimeInterval {
    var kinfo = kinfo_proc()
    var size = MemoryLayout<kinfo_proc>.stride
    var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
    sysctl(&mib, u_int(mib.count), &kinfo, &size, nil, 0)
    let startTime = kinfo.kp_proc.p_starttime
    return TimeInterval(startTime.tv_sec) + TimeInterval(startTime.tv_usec) / 1e6
}
