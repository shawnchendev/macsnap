import XCTest
@testable import MacsnapCore

final class SingleInstanceTests: XCTestCase {
    func testLockAcquireAndRelease() {
        let testPath = "/tmp/macsnap-test-\(UUID().uuidString).lock"
        let lock1 = SingleInstanceLock(customPath: testPath)
        let res1 = lock1.acquire(isTakeover: false)
        guard case .acquired = res1 else {
            XCTFail("Expected acquired, got \(res1)")
            return
        }

        // Second lock by same process reports dismissed/active
        let lock2 = SingleInstanceLock(customPath: testPath)
        let res2 = lock2.acquire(isTakeover: false)
        guard case .dismissedRunningInstance = res2 else {
            XCTFail("Expected dismissedRunningInstance, got \(res2)")
            return
        }

        lock1.release()

        // Now lock2 can acquire
        let res3 = lock2.acquire(isTakeover: false)
        guard case .acquired = res3 else {
            XCTFail("Expected acquired after release, got \(res3)")
            return
        }
        lock2.release()
    }
}
