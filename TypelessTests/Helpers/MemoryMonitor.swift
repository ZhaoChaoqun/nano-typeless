import Foundation

/// 进程内存监控工具
struct MemoryMonitor {

    /// 获取当前进程的常驻内存 (RSS) 大小，单位 MB
    static func currentRSSInMB() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return -1.0 }
        return Double(info.resident_size) / 1_048_576.0
    }

    /// 记录内存快照
    struct Snapshot {
        let label: String
        let rssMB: Double
        let timestamp: Date
    }

    /// 内存跟踪器
    class Tracker {
        private(set) var snapshots: [Snapshot] = []

        func record(label: String) {
            snapshots.append(Snapshot(
                label: label,
                rssMB: MemoryMonitor.currentRSSInMB(),
                timestamp: Date()
            ))
        }

        /// 计算从首次快照到最后一次快照的内存增长 (MB)
        var totalGrowthMB: Double {
            guard let first = snapshots.first, let last = snapshots.last else { return 0 }
            return last.rssMB - first.rssMB
        }

        /// 打印所有快照
        func printReport() {
            let baseline = snapshots.first?.rssMB ?? 0
            for snap in snapshots {
                let delta = snap.rssMB - baseline
                print(String(format: "  [MEM] %-20s  RSS: %.1f MB  (Δ %.1f MB)",
                             (snap.label as NSString).utf8String ?? "", snap.rssMB, delta))
            }
        }
    }
}
