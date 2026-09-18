import Foundation

/// Walks parent pids. The hook is a child of the agent, which is a child of the
/// shell, which is a child of the terminal, so the chain is how Squawk learns
/// which terminal a request came from without the terminal telling it.
public enum ProcessTree {
    public static func parent(of pid: pid_t) -> pid_t? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        let result = mib.withUnsafeMutableBufferPointer { buffer in
            sysctl(buffer.baseAddress, 4, &info, &size, nil, 0)
        }
        guard result == 0, size > 0 else { return nil }
        let ppid = info.kp_eproc.e_ppid
        return ppid > 1 ? ppid : nil
    }

    /// The controlling terminal of a process, as /dev/ttysNNN. Read from the
    /// process table rather than from file descriptors: a hook is spawned with
    /// its streams redirected and often has no controlling terminal of its own,
    /// which is why asking about itself came back empty.
    public static func controllingTTY(of pid: pid_t) -> String? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        let result = mib.withUnsafeMutableBufferPointer { buffer in
            sysctl(buffer.baseAddress, 4, &info, &size, nil, 0)
        }
        guard result == 0, size > 0 else { return nil }
        let device = info.kp_eproc.e_tdev
        guard device != -1, device != 0 else { return nil }
        guard let name = devname(device, S_IFCHR) else { return nil }
        return "/dev/" + String(cString: name)
    }

    /// The nearest ancestor that has a terminal, which is the agent's pane.
    public static func nearestTTY(from pid: pid_t = getpid(), limit: Int = 12) -> String? {
        if let own = controllingTTY(of: pid) { return own }
        for parent in ancestors(of: pid, limit: limit) {
            if let tty = controllingTTY(of: parent) { return tty }
        }
        return nil
    }

    /// Nearest ancestor first. The limit keeps a cycle or a very deep tree from
    /// turning a hook that must stay cheap into a long walk.
    public static func ancestors(of pid: pid_t = getpid(), limit: Int = 12) -> [pid_t] {
        var chain: [pid_t] = []
        var current = pid
        while chain.count < limit, let parent = parent(of: current) {
            chain.append(parent)
            current = parent
        }
        return chain
    }
}
