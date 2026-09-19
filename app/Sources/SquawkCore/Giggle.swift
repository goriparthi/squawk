import Foundation

/// The wiggle a tickled tummy gets: a side to side shimmy that dies away in
/// under a second, laid over whatever the pet is doing. Small on purpose.
public enum Giggle {
    public static let duration: TimeInterval = 0.9

    /// The overlay at `elapsed` seconds in; zero once it is over.
    public static func apply(to pose: inout Pose3D, at elapsed: TimeInterval) {
        guard elapsed >= 0, elapsed < duration else { return }
        let fade = 1 - elapsed / duration
        let wiggle = sin(elapsed * 2 * .pi * 5.5) * fade
        pose.sway += wiggle * 4
        pose.twist += wiggle * 3
        pose.headRoll += wiggle * 5
        pose.bob += abs(wiggle) * 0.012
        pose.leftShoulder += abs(wiggle) * 9
        pose.rightShoulder += abs(wiggle) * 9
    }
}
