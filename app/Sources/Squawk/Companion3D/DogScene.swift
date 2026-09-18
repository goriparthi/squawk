import AppKit
import Metal
import SceneKit
import SquawkCore

/// The four legged companion. A boxy chassis on four articulated legs with a
/// sensor head, built from the same primitives and lit the same way as the
/// biped, and driven by the same `Pose3D`: the front legs take the arm
/// channels and the hind legs the leg ones.
///
/// One unit is one head width, as everywhere else in the model.
@MainActor
final class DogScene {
    let scene = SCNScene()
    let root = SCNNode()
    let bodyPivot = SCNNode()
    let headPivot = SCNNode()
    let screen = SCNNode()
    /// Its back, which is what you rub.
    let tummy = SCNNode()

    /// Front pair then hind pair, left before right.
    private var uppers: [SCNNode] = []
    private var lowers: [SCNNode] = []
    private var feet: [SCNNode] = []
    private let tail = SCNNode()
    private let shadow = SCNNode()
    private let cameraNode = SCNNode()

    private var shellMaterials: [(material: SCNMaterial, resting: NSColor)] = []
    private(set) var persona: Persona

    private enum Size {
        /// Long, low and square: a chassis rather than a torso.
        static let body = SCNVector3(0.52, 0.34, 1.02)
        static let head = CGFloat(0.42)
        static let neck = CGFloat(0.26)
        static let upperLeg = CGFloat(0.30)
        static let lowerLeg = CGFloat(0.30)
        static let legThickness = CGFloat(0.058)
        /// How far the legs sit from the centre line and from each other.
        static let track = CGFloat(0.23)
        static let wheelbase = CGFloat(0.36)
        static let visor = CGSize(width: head * 0.80, height: head * 0.60)
    }

    init(persona: Persona = Cast.default) {
        self.persona = persona
        scene.background.contents = NSColor.clear
        scene.rootNode.addChildNode(root)
        root.addChildNode(bodyPivot)

        buildChassis()
        buildHead()
        buildLegs()
        buildTail()
        buildShadow()
        buildLights()
        buildCamera()
    }

    // MARK: - Materials

    private func shell(_ colour: NSColor, shine: CGFloat = 0.3) -> SCNMaterial {
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        material.diffuse.contents = colour
        material.metalness.contents = 0.12
        material.roughness.contents = 1 - shine
        shellMaterials.append((material, colour))
        return material
    }

    private func accented() -> SCNMaterial {
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        material.diffuse.contents = CompanionScene.colour(persona.accent)
        material.emission.contents = CompanionScene.colour(persona.accent, scale: 0.22)
        material.metalness.contents = 0.2
        material.roughness.contents = 0.45
        shellMaterials.append((material, CompanionScene.colour(persona.accent)))
        return material
    }

    private func glass() -> SCNMaterial {
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        material.diffuse.contents = Palette.faceBottom
        material.roughness.contents = 0.22
        return material
    }

    // MARK: - Parts

    private func buildChassis() {
        let box = SCNBox(width: Size.body.x, height: Size.body.y, length: Size.body.z,
                         chamferRadius: Size.body.y * 0.34)
        box.chamferSegmentCount = 10
        box.materials = [shell(CompanionScene.colour(persona.shell))]
        tummy.addChildNode(SCNNode(geometry: box))
        bodyPivot.addChildNode(tummy)

        // A darker deck along the top, which is what stops a single box reading
        // as a brick.
        let deck = SCNBox(width: Size.body.x * 0.82, height: Size.body.y * 0.30,
                          length: Size.body.z * 0.74, chamferRadius: Size.body.y * 0.14)
        deck.chamferSegmentCount = 8
        deck.materials = [shell(Palette.line, shine: 0.42)]
        let deckNode = SCNNode(geometry: deck)
        deckNode.position = SCNVector3(0, Size.body.y * 0.52, -Size.body.z * 0.04)
        tummy.addChildNode(deckNode)

        // A strip down each flank, in the character's accent.
        for side in [-1, 1] as [CGFloat] {
            let strip = SCNBox(width: 0.02, height: Size.body.y * 0.16,
                               length: Size.body.z * 0.52, chamferRadius: 0.008)
            strip.materials = [accented()]
            let node = SCNNode(geometry: strip)
            node.position = SCNVector3(side * Size.body.x * 0.5, 0, 0)
            tummy.addChildNode(node)
        }
    }

    private func buildHead() {
        // Forward and a little above the chassis, on a short neck.
        headPivot.position = SCNVector3(0, Size.body.y * 0.55, Size.body.z * 0.5 + Size.neck * 0.3)
        bodyPivot.addChildNode(headPivot)

        let neck = SCNBox(width: Size.head * 0.34, height: Size.head * 0.30,
                          length: Size.neck, chamferRadius: Size.head * 0.12)
        neck.materials = [shell(Palette.line)]
        let neckNode = SCNNode(geometry: neck)
        neckNode.position = SCNVector3(0, -Size.head * 0.2, -Size.neck * 0.45)
        headPivot.addChildNode(neckNode)

        let box = SCNBox(width: Size.head, height: Size.head * 0.82,
                         length: Size.head * 0.74, chamferRadius: Size.head * 0.2)
        box.chamferSegmentCount = 10
        box.materials = [shell(CompanionScene.colour(persona.shell), shine: 0.38)]
        headPivot.addChildNode(SCNNode(geometry: box))

        // The same face panel the biped wears, on the front of the sensor head.
        let visor = SCNBox(width: Size.visor.width, height: Size.visor.height,
                           length: 0.04, chamferRadius: Size.visor.height * 0.3)
        visor.chamferSegmentCount = 10
        visor.materials = [glass()]
        let visorNode = SCNNode(geometry: visor)
        visorNode.position = SCNVector3(0, 0, Size.head * 0.37 - 0.004)
        headPivot.addChildNode(visorNode)

        let plane = SCNPlane(width: Size.visor.width, height: Size.visor.height)
        let lit = SCNMaterial()
        lit.lightingModel = .constant
        lit.blendMode = .add
        lit.diffuse.magnificationFilter = .linear
        lit.diffuse.minificationFilter = .linear
        plane.materials = [lit]
        screen.geometry = plane
        screen.position = SCNVector3(0, 0, Size.head * 0.37 + 0.018)
        headPivot.addChildNode(screen)

        // Ears, which is the whole difference between a sensor and a dog.
        for side in [-1, 1] as [CGFloat] {
            let ear = SCNBox(width: Size.head * 0.20, height: Size.head * 0.42,
                             length: 0.035, chamferRadius: Size.head * 0.08)
            ear.materials = [accented()]
            let node = SCNNode(geometry: ear)
            node.position = SCNVector3(side * Size.head * 0.34, Size.head * 0.52, -Size.head * 0.06)
            node.eulerAngles = SCNVector3(CompanionScene.radians(-12), 0,
                                          CompanionScene.radians(Double(side) * -14))
            headPivot.addChildNode(node)
        }
    }

    /// Front pair then hind pair, left before right, which is the order the
    /// pose channels are read in.
    private func buildLegs() {
        for (index, corner) in [(-1.0, 1.0), (1.0, 1.0), (-1.0, -1.0), (1.0, -1.0)].enumerated() {
            let front = index < 2
            let upper = SCNNode()
            upper.position = SCNVector3(
                CGFloat(corner.0) * Size.track,
                -Size.body.y * 0.30,
                CGFloat(corner.1) * Size.wheelbase
            )
            tummy.addChildNode(upper)

            let hipCap = SCNSphere(radius: Size.legThickness * 1.7)
            hipCap.segmentCount = 24
            hipCap.materials = [shell(Palette.line)]
            upper.addChildNode(SCNNode(geometry: hipCap))

            let thigh = SCNBox(width: Size.legThickness * 1.5, height: Size.upperLeg,
                               length: Size.legThickness * 2.4,
                               chamferRadius: Size.legThickness * 0.6)
            thigh.chamferSegmentCount = 6
            thigh.materials = [shell(CompanionScene.colour(persona.shell))]
            let thighNode = SCNNode(geometry: thigh)
            thighNode.position = SCNVector3(0, -Size.upperLeg / 2, 0)
            upper.addChildNode(thighNode)

            let lower = SCNNode()
            lower.position = SCNVector3(0, -Size.upperLeg, 0)
            upper.addChildNode(lower)

            let jointCap = SCNSphere(radius: Size.legThickness * 1.15)
            jointCap.segmentCount = 20
            jointCap.materials = [accented()]
            lower.addChildNode(SCNNode(geometry: jointCap))

            let shin = SCNBox(width: Size.legThickness * 1.15, height: Size.lowerLeg,
                              length: Size.legThickness * 1.5,
                              chamferRadius: Size.legThickness * 0.5)
            shin.chamferSegmentCount = 6
            shin.materials = [shell(Palette.line)]
            let shinNode = SCNNode(geometry: shin)
            shinNode.position = SCNVector3(0, -Size.lowerLeg / 2, 0)
            lower.addChildNode(shinNode)

            let foot = SCNNode()
            foot.position = SCNVector3(0, -Size.lowerLeg, 0)
            lower.addChildNode(foot)

            let pad = SCNSphere(radius: Size.legThickness * 1.25)
            pad.segmentCount = 20
            pad.materials = [shell(Palette.shellTop)]
            foot.addChildNode(SCNNode(geometry: pad))

            uppers.append(upper)
            lowers.append(lower)
            feet.append(foot)
        }
    }

    private func buildTail() {
        tail.position = SCNVector3(0, Size.body.y * 0.4, -Size.body.z * 0.5)
        tummy.addChildNode(tail)

        let stalk = SCNCylinder(radius: 0.012, height: Size.head * 0.5)
        stalk.radialSegmentCount = 14
        stalk.materials = [shell(Palette.rim)]
        let stalkNode = SCNNode(geometry: stalk)
        stalkNode.position = SCNVector3(0, Size.head * 0.22, -Size.head * 0.08)
        stalkNode.eulerAngles = SCNVector3(CompanionScene.radians(28), 0, 0)
        tail.addChildNode(stalkNode)

        let tip = SCNSphere(radius: 0.038)
        tip.segmentCount = 24
        tip.materials = [accented()]
        let tipNode = SCNNode(geometry: tip)
        tipNode.position = SCNVector3(0, Size.head * 0.44, -Size.head * 0.20)
        tail.addChildNode(tipNode)
    }

    private func buildShadow() {
        let plane = SCNPlane(width: 1.15, height: 0.62)
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = CompanionScene.shadowImage()
        material.blendMode = .alpha
        material.writesToDepthBuffer = false
        plane.materials = [material]
        shadow.geometry = plane
        shadow.eulerAngles = SCNVector3(-CGFloat.pi / 2, 0, 0)
        shadow.position = SCNVector3(0, -0.76, 0)
        shadow.renderingOrder = -10
        root.addChildNode(shadow)
    }

    private func buildLights() {
        CompanionScene.addStandardLights(to: scene)
    }

    /// Further back and a little to one side, because a long body seen dead on
    /// is a square. Three quarters is the only angle a quadruped reads from.
    private func buildCamera() {
        let camera = SCNCamera()
        camera.fieldOfView = 30
        camera.projectionDirection = .vertical
        camera.zNear = 0.1
        camera.zFar = 100
        camera.wantsHDR = true
        camera.bloomIntensity = 1.1
        camera.bloomThreshold = 0.45
        camera.bloomBlurRadius = 14
        camera.wantsExposureAdaptation = false
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(1.66, 0.52, 3.32)
        cameraNode.eulerAngles = SCNVector3(CompanionScene.radians(-7),
                                            CompanionScene.radians(26), 0)
        scene.rootNode.addChildNode(cameraNode)
    }

    var pointOfView: SCNNode { cameraNode }

    // MARK: - Posing

    /// The arm channels drive the front legs and the leg channels the hind
    /// ones, which is what lets a dog share every pose the biped has.
    func apply(_ pose: Pose3D) {
        let upperAngles = [pose.leftShoulder, pose.rightShoulder, pose.leftHip, pose.rightHip]
        let lowerAngles = [pose.leftElbow, pose.rightElbow, pose.leftKnee, pose.rightKnee]
        let footAngles = [0, 0, pose.leftAnkle, pose.rightAnkle]

        for index in uppers.indices {
            uppers[index].eulerAngles.x = CompanionScene.radians(-upperAngles[index])
            lowers[index].eulerAngles.x = CompanionScene.radians(lowerAngles[index])
            feet[index].eulerAngles.x = CompanionScene.radians(-footAngles[index])
        }

        bodyPivot.position.y = CGFloat(pose.bob)
        bodyPivot.eulerAngles = SCNVector3(CompanionScene.radians(pose.lean),
                                           CompanionScene.radians(pose.twist + pose.spin),
                                           CompanionScene.radians(pose.sway))
        headPivot.eulerAngles = SCNVector3(CompanionScene.radians(pose.headPitch),
                                            CompanionScene.radians(pose.headYaw),
                                            CompanionScene.radians(pose.headRoll))
        // A tail is the one part of a dog that says everything. It wags with
        // whatever the body is doing.
        tail.eulerAngles.z = CompanionScene.radians(pose.sway * 3 + pose.headRoll * 1.5)
        tail.eulerAngles.x = CompanionScene.radians(-pose.lean * 0.5)
        root.position.x = CGFloat(pose.travel)
    }

    func paintFace(_ artist: FaceArtist) {
        CompanionScene.paint(artist, into: screen, context: faceContext, texture: faceTexture)
    }

    func tint(_ colour: NSColor?) {
        for part in shellMaterials {
            part.material.diffuse.contents = colour ?? part.resting
        }
    }

    func tint(hue: Double) {
        let colour = Dance.colour(at: hue)
        tint(NSColor(calibratedHue: CGFloat(colour.hue), saturation: CGFloat(colour.saturation),
                     brightness: CGFloat(colour.brightness), alpha: 1))
    }

    private lazy var faceContext: CGContext? = CompanionScene.makeFaceContext()
    private lazy var faceTexture: MTLTexture? = CompanionScene.makeFaceTexture(for: screen)
}
