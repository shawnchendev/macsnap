import Foundation

public final class SingleInstanceLock: @unchecked Sendable {
    public let lockPath: String
    private var fileDescriptor: Int32 = -1

    public init(customPath: String? = nil) {
        if let custom = customPath {
            self.lockPath = custom
        } else {
            let uid = getuid()
            let runtimeDir = "/tmp/macsnap-\(uid)"
            try? FileManager.default.createDirectory(atPath: runtimeDir, withIntermediateDirectories: true)
            self.lockPath = "\(runtimeDir)/instance.lock"
        }
    }

    public enum AcquireResult {
        case acquired
        case dismissedRunningInstance
        case failed(String)
    }

    /// Tries to acquire lock. If already running, behavior depends on `isTakeover` (e.g. --file or --clipboard):
    /// - If not takeover: sends SIGTERM to running instance to dismiss it, returns `.dismissedRunningInstance`
    /// - If takeover: sends SIGTERM to running instance, waits up to 2 seconds, then acquires lock.
    public func acquire(isTakeover: Bool = false) -> AcquireResult {
        if FileManager.default.fileExists(atPath: lockPath) {
            if let pidStr = try? String(contentsOfFile: lockPath, encoding: .utf8),
               let pid = pid_t(pidStr.trimmingCharacters(in: .whitespacesAndNewlines)) {
                // If it is another active process
                if pid != getpid() && kill(pid, 0) == 0 {
                    // Send SIGTERM to toggle/dismiss it
                    kill(pid, SIGTERM)

                    if !isTakeover {
                        // Toggle hotkey: dismissed running overlay!
                        return .dismissedRunningInstance
                    }

                    // Takeover: wait up to 2.0s for process to exit
                    let deadline = Date().addingTimeInterval(2.0)
                    while Date() < deadline {
                        if kill(pid, 0) != 0 {
                            break
                        }
                        usleep(50_000) // 50ms
                    }
                } else if pid == getpid() {
                    // Same process already owns the lock
                    return .dismissedRunningInstance
                }
            }
            // Clean up stale or exited lock
            try? FileManager.default.removeItem(atPath: lockPath)
        }

        // Now acquire lock
        let fd = open(lockPath, O_CREAT | O_RDWR | O_EXCL, 0o600)
        if fd < 0 {
            // Retry once if file was in middle of removal
            usleep(50_000)
            let fdRetry = open(lockPath, O_CREAT | O_RDWR, 0o600)
            if fdRetry < 0 {
                return .failed("Could not acquire instance lock at \(lockPath)")
            }
            self.fileDescriptor = fdRetry
        } else {
            self.fileDescriptor = fd
        }

        let pidString = "\(getpid())\n"
        if let data = pidString.data(using: .utf8) {
            data.withUnsafeBytes { ptr in
                _ = write(self.fileDescriptor, ptr.baseAddress, ptr.count)
            }
        }

        return .acquired
    }

    public func release() {
        if fileDescriptor >= 0 {
            close(fileDescriptor)
            fileDescriptor = -1
        }
        try? FileManager.default.removeItem(atPath: lockPath)
    }

    deinit {
        release()
    }
}
