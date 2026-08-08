import Darwin
import Foundation
import IOKit.ps

struct SystemMetrics: Equatable {
    let batteryLevel: Double?
    let isCharging: Bool
    let cpuUsage: Double
    let memoryUsage: Double

    static let empty = SystemMetrics(
        batteryLevel: nil,
        isCharging: false,
        cpuUsage: 0,
        memoryUsage: 0
    )

    var healthLabel: String {
        if let batteryLevel, batteryLevel <= 0.15, !isCharging {
            return "Low battery"
        }
        if cpuUsage >= 0.90 || memoryUsage >= 0.92 {
            return "High load"
        }
        if cpuUsage >= 0.70 || memoryUsage >= 0.80 {
            return "Working"
        }
        return "Healthy"
    }

    var batterySymbol: String {
        guard let batteryLevel else { return "battery.0percent" }
        switch batteryLevel {
        case 0.88...: return "battery.100percent"
        case 0.63...: return "battery.75percent"
        case 0.38...: return "battery.50percent"
        case 0.13...: return "battery.25percent"
        default: return "battery.0percent"
        }
    }
}

final class SystemMonitor {
    private struct CPUTicks {
        let user: UInt64
        let system: UInt64
        let idle: UInt64
        let nice: UInt64

        var total: UInt64 { user + system + idle + nice }
    }

    private var previousCPUTicks: CPUTicks?
    private var lastCPUUsage = 0.0

    func sample() -> SystemMetrics {
        let battery = readBattery()
        return SystemMetrics(
            batteryLevel: battery?.level,
            isCharging: battery?.isCharging ?? false,
            cpuUsage: readCPUUsage(),
            memoryUsage: readMemoryUsage()
        )
    }

    private func readBattery() -> (level: Double, isCharging: Bool)? {
        guard let powerSourcesInfo = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sourceList = IOPSCopyPowerSourcesList(powerSourcesInfo)?.takeRetainedValue() as? [CFTypeRef] else {
            return nil
        }

        for source in sourceList {
            guard let description = IOPSGetPowerSourceDescription(powerSourcesInfo, source)?
                .takeUnretainedValue() as? [String: Any],
                  let currentCapacity = description[kIOPSCurrentCapacityKey] as? Double,
                  let maximumCapacity = description[kIOPSMaxCapacityKey] as? Double,
                  maximumCapacity > 0 else {
                continue
            }

            return (
                level: min(max(currentCapacity / maximumCapacity, 0), 1),
                isCharging: description[kIOPSIsChargingKey] as? Bool ?? false
            )
        }

        return nil
    }

    private func readCPUUsage() -> Double {
        var cpuLoad = host_cpu_load_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size
        )

        let result = withUnsafeMutablePointer(to: &cpuLoad) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPointer in
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, reboundPointer, &count)
            }
        }

        guard result == KERN_SUCCESS else { return lastCPUUsage }

        let current = CPUTicks(
            user: UInt64(cpuLoad.cpu_ticks.0),
            system: UInt64(cpuLoad.cpu_ticks.1),
            idle: UInt64(cpuLoad.cpu_ticks.2),
            nice: UInt64(cpuLoad.cpu_ticks.3)
        )
        defer { previousCPUTicks = current }

        guard let previousCPUTicks else { return lastCPUUsage }
        let totalDelta = current.total &- previousCPUTicks.total
        let idleDelta = current.idle &- previousCPUTicks.idle
        guard totalDelta > 0 else { return lastCPUUsage }

        lastCPUUsage = min(max(1 - Double(idleDelta) / Double(totalDelta), 0), 1)
        return lastCPUUsage
    }

    private func readMemoryUsage() -> Double {
        var statistics = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size
        )

        let result = withUnsafeMutablePointer(to: &statistics) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPointer in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, reboundPointer, &count)
            }
        }

        guard result == KERN_SUCCESS else { return 0 }

        var pageSize: vm_size_t = 0
        guard host_page_size(mach_host_self(), &pageSize) == KERN_SUCCESS else { return 0 }

        let usedPages = UInt64(statistics.active_count)
            + UInt64(statistics.wire_count)
            + UInt64(statistics.compressor_page_count)
        let usedBytes = usedPages * UInt64(pageSize)
        let totalBytes = ProcessInfo.processInfo.physicalMemory
        guard totalBytes > 0 else { return 0 }

        return min(max(Double(usedBytes) / Double(totalBytes), 0), 1)
    }
}
