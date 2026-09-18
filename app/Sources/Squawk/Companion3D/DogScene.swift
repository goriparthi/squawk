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
    /// Worn while audio is playing.
    let headphones = SCNNode()
    let meter = SCNNode()
    let indicator = SCNNode()
    private var bars: [SCNNode] = []
    private var stripMaterials: [SCNMaterial] = []
    private var indicatorMaterial: SCNMaterial?

    /// Front pair then hind pair, left before right.
    private var uppers: [SCNNode] = []
    private var lowers: [SCNNode] = []
    private var feet: [SCNNode] = []
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
        buildShadow()
        buildLights()
        buildCamera()
    }

    // MARK: - Materials

    private func shell(_ colour: NSColor, shine: CGFloat = 0.3) -> SCNMaterial {
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        material.diffuse.contents = colour
        material.metalness.contents = 0.62
        material.roughness.contents = max(0.18, 1 - shine - 0.18)
        shellMaterials.append((material, colour))
        return material
    }

    private func accented() -> SCNMaterial {
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        material.diffuse.contents = CompanionScene.colour(persona.accent)
        material.emission.contents = CompanionScene.colour(persona.accent, scale: 0.22)
        material.metalness.contents = 0.55
        material.roughness.contents = 0.3
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
            let material = accented()
            stripMaterials.append(material)
            strip.materials = [material]
            let node = SCNNode(geometry: strip)
            node.position = SCNVector3(side * Size.body.x * 0.5, 0, 0)
            tummy.addChildNode(node)
        }

        // The meter runs along the near flank, which is the only large flat
        // panel a four legged body has facing the camera.
        meter.isHidden = true
        tummy.addChildNode(meter)
        let width = Size.body.z * 0.07
        let gap = Size.body.z * 0.035
        let span = CGFloat(Spectrum.bandCount - 1) * (width + gap)
        for band in 0..<Spectrum.bandCount {
            let bar = SCNBox(width: 0.022, height: Self.meterHeight, length: width,
                             chamferRadius: 0.008)
            bar.chamferSegmentCount = 5
            bar.materials = [accented()]
            let node = SCNNode(geometry: bar)
            node.position = SCNVector3(0, Self.meterHeight / 2, 0)
            let pivot = SCNNode()
            pivot.position = SCNVector3(Size.body.x * 0.51, -Size.body.y * 0.18,
                                        -span / 2 + CGFloat(band) * (width + gap))
            pivot.addChildNode(node)
            meter.addChildNode(pivot)
            bars.append(pivot)
        }

        // A beacon on the deck, where a real one carries its light.
        indicator.isHidden = true
        let lamp = SCNSphere(radius: Size.body.y * 0.16)
        lamp.segmentCount = 22
        let lampMaterial = SCNMaterial()
        lampMaterial.lightingModel = .constant
        lampMaterial.diffuse.contents = NSColor.white
        indicatorMaterial = lampMaterial
        lamp.materials = [lampMaterial]
        indicator.addChildNode(SCNNode(geometry: lamp))
        indicator.position = SCNVector3(0, Size.body.y * 0.72, -Size.body.z * 0.26)
        tummy.addChildNode(indicator)
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

        let shroud = SCNBox(width: Size.head * 1.04, height: Size.head * 0.86,
                            length: Size.head * 0.62, chamferRadius: Size.head * 0.16)
        shroud.chamferSegmentCount = 10
        shroud.materials = [shell(CompanionScene.colour(persona.shell), shine: 0.42)]
        headPivot.addChildNode(SCNNode(geometry: shroud))

        let sensors = SCNBox(width: Size.head * 0.88, height: Size.head * 0.68,
                             length: Size.head * 0.74, chamferRadius: Size.head * 0.1)
        sensors.chamferSegmentCount = 8
        sensors.materials = [shell(Palette.faceBottom, shine: 0.5)]
        headPivot.addChildNode(SCNNode(geometry: sensors))

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

        // Worn only while something is playing.
        headphones.isHidden = true
        headPivot.addChildNode(headphones)
        for side in [-1, 1] as [CGFloat] {
            let cup = SCNCylinder(radius: Size.head * 0.26, height: Size.head * 0.13)
            cup.radialSegmentCount = 32
            cup.materials = [shell(Palette.line, shine: 0.4)]
            let node = SCNNode(geometry: cup)
            node.eulerAngles = SCNVector3(0, 0, CGFloat.pi / 2)
            node.position = SCNVector3(side * Size.head * 0.58, -Size.head * 0.02, 0)
            headphones.addChildNode(node)

            let pad = SCNCylinder(radius: Size.head * 0.20, height: Size.head * 0.15)
            pad.radialSegmentCount = 32
            pad.materials = [accented()]
            let padNode = SCNNode(geometry: pad)
            padNode.eulerAngles = SCNVector3(0, 0, CGFloat.pi / 2)
            padNode.position = SCNVector3(side * Size.head * 0.54, -Size.head * 0.02, 0)
            headphones.addChildNode(padNode)
        }
        let band = SCNTorus(ringRadius: Size.head * 0.62, pipeRadius: Size.head * 0.06)
        band.ringSegmentCount = 40
        band.pipeSegmentCount = 14
        band.materials = [accented()]
        let bandNode = SCNNode(geometry: band)
        bandNode.eulerAngles = SCNVector3(CGFloat.pi / 2, 0, 0)
        bandNode.position = SCNVector3(0, Size.head * 0.14, Size.head * 0.04)
        headphones.addChildNode(bandNode)
    }

    /// Front pair then hind pair, left before right, which is the order the
    /// pose channels are read in.
    private func buildLegs() {
        for corner in [(-1.0, 1.0), (1.0, 1.0), (-1.0, -1.0), (1.0, -1.0)] {
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
        // Metal is only metal because of what it reflects. With nothing in the
        // environment a metalness of 0.6 renders as black plastic.
        scene.lightingEnvironment.contents = CompanionScene.studioEnvironment()
        scene.lightingEnvironment.intensity = 1.6
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
        root.position.x = CGFloat(pose.travel)
    }

    static let meterHeight = CGFloat(0.09)

    func show(_ spectrum: Spectrum?) {
        guard let spectrum, !spectrum.isSilent else {
            meter.isHidden = true
            return
        }
        meter.isHidden = false
        for (index, bar) in bars.enumerated() where index < spectrum.bands.count {
            bar.scale.y = CGFloat(max(0.26, spectrum.bands[index]))
        }
    }

    func light(_ state: PrivacyState) {
        guard let light = state.light else {
            indicator.isHidden = true
            return
        }
        indicator.isHidden = false
        let colour = CompanionScene.colour(light.tone)
        indicatorMaterial?.diffuse.contents = colour
        indicatorMaterial?.emission.contents = colour
    }

    func paintFace(_ artist: FaceArtist) {
        CompanionScene.paint(artist, into: screen, context: faceContext,
                             texture: faceTexture, staging: faceStaging)
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
    private lazy var faceStaging: MTLTexture? = CompanionScene.makeStagingTexture()
    private lazy var faceTexture: MTLTexture? = CompanionScene.makeFaceTexture(for: screen)
}
