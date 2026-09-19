import XCTest
@testable import SquawkCore

final class GiggleTests: XCTestCase {
    func testItWigglesBothWaysAndThenStops() {
        var signs: Set<Bool> = []
        for step in 0..<20 {
            var pose = Pose3D()
            Giggle.apply(to: &pose, at: Double(step) * 0.04)
            if abs(pose.sway) > 0.5 { signs.insert(pose.sway > 0) }
        }
        XCTAssertEqual(signs, [true, false], "a giggle rocks to both sides")
        var pose = Pose3D()
        Giggle.apply(to: &pose, at: Giggle.duration)
        XCTAssertEqual(pose, Pose3D(), "and leaves the pose alone once it is over")
    }
}
