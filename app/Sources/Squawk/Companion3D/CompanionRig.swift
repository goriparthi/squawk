import AppKit
import SceneKit
import SquawkCore

/// What the view needs from a body, whatever shape it is. Both rigs take the
/// same `Pose3D`, so the springs, the moods, the walk and the dance are written
/// once and neither rig knows the other exists.
@MainActor
protocol CompanionRig: AnyObject {
    var scene: SCNScene { get }
    var pointOfView: SCNNode { get }
    /// The part a rub or a double tap counts against: the belly of a biped, the
    /// back of a dog.
    var tummy: SCNNode { get }

    /// Shown while something is playing.
    var headphones: SCNNode { get }

    func apply(_ pose: Pose3D)
    func paintFace(_ artist: FaceArtist)
    func tint(_ colour: NSColor?)
    func tint(hue: Double)
    /// Where it stands when it is doing nothing, which differs: a dog's legs
    /// are never straight.
    var restingPose: Pose3D { get }
}

extension CompanionScene: CompanionRig {
    var tummy: SCNNode { bodyPivot }
    var restingPose: Pose3D { Pose3D() }
}

extension DogScene: CompanionRig {
    var restingPose: Pose3D { Trot.standing() }
}

/// Which rig a character wants.
@MainActor
enum Rigs {
    static func make(for persona: Persona) -> any CompanionRig {
        switch persona.build {
        case .biped: CompanionScene(persona: persona)
        case .quadruped: DogScene(persona: persona)
        }
    }

    /// The gait that suits a build. Two legs stride, four legs trot.
    static func walk(_ build: Build, phase: Double, effort: Double) -> Pose3D {
        switch build {
        case .biped: Gait.pose(phase: phase, effort: effort)
        case .quadruped: Trot.pose(phase: phase, effort: effort)
        }
    }
}
