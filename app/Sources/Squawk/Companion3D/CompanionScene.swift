import AppKit
import Metal
import SceneKit
import SquawkCore

/// The companion as geometry rather than a drawing. Built in code from
/// primitives: there is no model file to lose, it scales to any size without
/// an asset pipeline, and the repo keeps its promise of no dependencies.
///
/// One unit is one head width, so everything below reads as a proportion the
/// way `BodyGeometry` does for the flat drawing.
@MainActor
final class CompanionScene {
    let scene = SCNScene()

    let root = SCNNode()
    let bodyPivot = SCNNode()
    let headPivot = SCNNode()
    let screen = SCNNode()
    /// Worn while audio is playing.
    let headphones = SCNNode()
    /// The chest badge, and the meter that replaces it while music plays.
    let badge = SCNNode()
    let meter = SCNNode()
    /// The microphone and camera lamp.
    let indicator = SCNNode()
    private var bars: [SCNNode] = []
    private var indicatorMaterial: SCNMaterial?

    let shoulders: (left: SCNNode, right: SCNNode)
    let elbows: (left: SCNNode, right: SCNNode)
    let hips: (left: SCNNode, right: SCNNode)
    let knees: (left: SCNNode, right: SCNNode)
    let ankles: (left: SCNNode, right: SCNNode)
    /// Three fingers and a thumb per hand, in that order, each on its own
    /// knuckle so a gesture is a set of angles rather than a swapped model.
    private(set) var knuckles: (left: [SCNNode], right: [SCNNode]) = ([], [])
    private let shadow = SCNNode()
    private let cameraNode = SCNNode()

    /// Every material that takes the rainbow during a dance, so the dance does
    /// not have to know how the model is put together.
    private var shellMaterials: [(material: SCNMaterial, resting: NSColor)] = []
    private var accentMaterials: [SCNMaterial] = []
    /// Who is on screen. The whole cast is one model in different colours.
    private(set) var persona: Persona = Cast.default

    // Proportions. Deliberately not the flat drawing's: a body seen in
    // perspective needs real depth and legs the drawing never had.
    private enum Size {
        static let body = SCNVector3(0.98, 0.86, 0.82)
        static let head = CGFloat(0.94)
        static let headDepth = CGFloat(0.78)
        static let neck = CGFloat(0.30)
        static let armLength = CGFloat(0.32)
        static let armThickness = CGFloat(0.095)
        static let legLength = CGFloat(0.22)
        static let legThickness = CGFloat(0.11)
        static let hipSpread = CGFloat(0.22)
        /// How square every rounded section is. 2 is a ball; this is a robot.
        static let squareness = CGFloat(4.6)
        /// Chamfer as a share of a limb's thickness, so every part rounds off
        /// by the same amount whatever size it is.
        static let chamfer = CGFloat(0.34)
        /// The visor, as a share of the head. Wider than tall, the way a face
        /// panel is, and sat a little low on the head.
        static let visor = CGSize(width: head * 0.78, height: head * 0.66)
        static let visorCorner = CGFloat(head * 0.17)
        static let visorDrop = CGFloat(-head * 0.03)
    }

    init(persona: Persona = Cast.default) {
        self.persona = persona
        shoulders = (SCNNode(), SCNNode())
        elbows = (SCNNode(), SCNNode())
        hips = (SCNNode(), SCNNode())
        knees = (SCNNode(), SCNNode())
        ankles = (SCNNode(), SCNNode())

        scene.background.contents = NSColor.clear
        scene.rootNode.addChildNode(root)
        root.addChildNode(bodyPivot)

        buildBody()
        buildHead()
        buildArms()
        buildLegs()
        buildShadow()
        buildLights()
        buildCamera()
    }

    // MARK: - Materials

    /// The accent: ears, antenna and badge. Emissive, so the bloom pass catches
    /// it the way it catches the eyes.
    private func accented() -> SCNMaterial {
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        material.diffuse.contents = Self.colour(persona.accent)
        material.emission.contents = Self.colour(persona.accent, scale: 0.28)
        material.metalness.contents = 0.1
        material.roughness.contents = 0.5
        accentMaterials.append(material)
        return material
    }

    static func colour(_ tone: Tone, scale: Double = 1) -> NSColor {
        NSColor(srgbRed: CGFloat(tone.red * scale), green: CGFloat(tone.green * scale),
                blue: CGFloat(tone.blue * scale), alpha: 1)
    }

    private func shell(_ colour: NSColor, shine: CGFloat = 0.28) -> SCNMaterial {
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        material.diffuse.contents = colour
        material.metalness.contents = 0.08
        material.roughness.contents = 1 - shine
        shellMaterials.append((material, colour))
        return material
    }

    /// The scope. Near black and barely reflective, so the eyes on it are the
    /// only thing with any light of their own.
    private func glass() -> SCNMaterial {
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        material.diffuse.contents = Palette.faceBottom
        material.metalness.contents = 0.0
        material.roughness.contents = 0.22
        return material
    }

    /// A limb segment: a rounded box rather than a capsule, so it reads as
    /// built rather than inflated.
    private static func limb(thickness: CGFloat, length: CGFloat) -> SCNGeometry {
        let box = SCNBox(width: thickness * 1.7, height: length,
                         length: thickness * 1.7, chamferRadius: thickness * Size.chamfer * 1.7)
        box.chamferSegmentCount = 8
        return box
    }

    // MARK: - Parts

    private func buildBody() {
        // The same egg the flat drawing uses: narrow at the shoulders, widest
        // low down, rounded off at both ends so the revolve has no seam.
        let egg = Revolve.geometry(
            height: CGFloat(Size.body.y),
            radius: CGFloat(Size.body.x) / 2,
            depth: CGFloat(Size.body.z) / CGFloat(Size.body.x),
            squareness: Size.squareness
        ) { drop in
            // The shared function describes the taper down to the widest point
            // and then holds; the flat drawing closes the base with its own
            // path, so the revolve has to round it off itself.
            let taper = BodyGeometry.halfWidthFraction(atFractionBelowTop: drop)
            let toBase = max(0, (drop - 0.62) / 0.38)
            let base = (1 - pow(toBase, 2.8)).squareRoot()
            return taper * base
        }
        egg.materials = [shell(Self.colour(persona.shell))]
        bodyPivot.addChildNode(SCNNode(geometry: egg))

        // The badge: the same two shapes as its eyes, worn on the chest. The
        // reference does this and it is what ties the head to the body.
        for side in [-1, 1] as [CGFloat] {
            let pill = SCNBox(width: CGFloat(Size.body.x) * 0.17,
                              height: CGFloat(Size.body.y) * 0.13,
                              length: 0.03,
                              chamferRadius: CGFloat(Size.body.y) * 0.055)
            pill.chamferSegmentCount = 8
            pill.materials = [accented()]
            let node = SCNNode(geometry: pill)
            node.position = SCNVector3(side * CGFloat(Size.body.x) * 0.11,
                                       CGFloat(Size.body.y) * 0.12,
                                       CGFloat(Size.body.z) * 0.47)
            badge.addChildNode(node)
        }
        bodyPivot.addChildNode(badge)
        buildMeter()
        buildIndicator()
    }

    private func buildHead() {
        headPivot.position = SCNVector3(0, CGFloat(Size.body.y) * 0.5 + Size.neck, 0)
        bodyPivot.addChildNode(headPivot)

        // A squircle, which is what a rounded box with a big chamfer is.
        let box = SCNBox(width: Size.head, height: Size.head * 0.98,
                         length: Size.headDepth, chamferRadius: Size.head * 0.20)
        box.chamferSegmentCount = 12
        box.materials = [shell(Self.colour(persona.shell), shine: 0.38)]
        headPivot.addChildNode(SCNNode(geometry: box))

        // The visor: a rounded square panel, not a porthole. Both references
        // wear the face this way, and a square gives the expressions room at
        // the corners that a circle cut off.
        let scope = SCNBox(width: Size.visor.width, height: Size.visor.height,
                           length: 0.05, chamferRadius: Size.visorCorner)
        scope.chamferSegmentCount = 10
        scope.materials = [glass()]
        let scopeNode = SCNNode(geometry: scope)
        scopeNode.position = SCNVector3(0, Size.visorDrop, Size.headDepth / 2 - 0.005)
        headPivot.addChildNode(scopeNode)

        // The face is drawn, not modelled: the 2D artist already knows every
        // expression, so the screen is a texture it paints.
        // Exactly the visor, so the clipped face fills it and cannot reach past
        // it whatever the expression does.
        let plane = SCNPlane(width: Size.visor.width, height: Size.visor.height)
        let lit = SCNMaterial()
        lit.lightingModel = .constant
        lit.diffuse.contents = NSColor.clear
        lit.isDoubleSided = false
        lit.blendMode = .add
        lit.emission.contents = NSColor.clear
        lit.emission.contents = NSColor.clear
        lit.diffuse.magnificationFilter = .linear
        lit.diffuse.minificationFilter = .linear
        lit.diffuse.mipFilter = .linear
        lit.emission.magnificationFilter = .linear
        lit.emission.minificationFilter = .linear
        lit.emission.mipFilter = .linear
        // The face is painted every frame, so a cached mipmap chain would be
        // rebuilt every frame too, for a texture always seen close to head on.
        lit.diffuse.maxAnisotropy = 8
        plane.materials = [lit]
        screen.geometry = plane
        screen.position = SCNVector3(0, Size.visorDrop, Size.headDepth / 2 + 0.024)
        headPivot.addChildNode(screen)

        // Ear discs, the way the reference wears them: a cap on each side of
        // the head rather than a tab sticking out of it.
        for side in [-1, 1] as [CGFloat] {
            let ear = SCNCylinder(radius: Size.head * 0.15, height: Size.head * 0.07)
            ear.radialSegmentCount = 36
            ear.materials = [accented()]
            let node = SCNNode(geometry: ear)
            node.eulerAngles = SCNVector3(0, 0, CGFloat.pi / 2)
            node.position = SCNVector3(side * (Size.head * 0.50), -Size.head * 0.04, 0)
            headPivot.addChildNode(node)

            let rim = SCNCylinder(radius: Size.head * 0.17, height: Size.head * 0.05)
            rim.radialSegmentCount = 36
            rim.materials = [shell(Palette.shellTop)]
            let rimNode = SCNNode(geometry: rim)
            rimNode.eulerAngles = SCNVector3(0, 0, CGFloat.pi / 2)
            rimNode.position = SCNVector3(side * (Size.head * 0.47), -Size.head * 0.04, 0)
            headPivot.addChildNode(rimNode)
        }

        // The antenna, which is most of what makes it read as a character
        // rather than a appliance.
        let stalk = SCNCylinder(radius: Size.head * 0.018, height: Size.head * 0.30)
        stalk.radialSegmentCount = 16
        stalk.materials = [shell(Palette.rim)]
        let stalkNode = SCNNode(geometry: stalk)
        stalkNode.position = SCNVector3(0, Size.head * 0.62, 0)
        stalkNode.eulerAngles = SCNVector3(0, 0, Self.radians(-8))
        headPivot.addChildNode(stalkNode)

        buildHeadphones()

        let bulb = SCNSphere(radius: Size.head * 0.085)
        bulb.segmentCount = 32
        bulb.materials = [accented()]
        let bulbNode = SCNNode(geometry: bulb)
        bulbNode.position = SCNVector3(-Size.head * 0.04, Size.head * 0.78, 0)
        headPivot.addChildNode(bulbNode)
    }

    private func buildArms() {
        for (side, shoulder, elbow) in [(CGFloat(-1), shoulders.left, elbows.left),
                                        (CGFloat(1), shoulders.right, elbows.right)] {
            // High on the torso and just proud of its widest point, so the arm
            // hangs at the side and brushes the body rather than sinking into
            // it. Tucked inside instead, the arms disappeared behind the belly.
            shoulder.position = SCNVector3(
                side * CGFloat(Size.body.x) * 0.58, CGFloat(Size.body.y) * 0.24, 0)
            bodyPivot.addChildNode(shoulder)

            // The deltoid: wide enough to reach back inside the torso at every
            // angle the arm can take, so the joint never opens a gap.
            let cap = SCNSphere(radius: Size.armThickness * 1.85)
            cap.segmentCount = 32
            cap.materials = [shell(Self.colour(persona.shell))]
            shoulder.addChildNode(SCNNode(geometry: cap))

            let upper = Self.limb(thickness: Size.armThickness, length: Size.armLength)
            upper.materials = [shell(Palette.line)]
            let upperNode = SCNNode(geometry: upper)
            // Centred on its own pivot, so it hangs from the joint.
            upperNode.position = SCNVector3(0, -Size.armLength / 2, 0)
            shoulder.addChildNode(upperNode)

            elbow.position = SCNVector3(0, -Size.armLength, 0)
            shoulder.addChildNode(elbow)

            let joint = SCNSphere(radius: Size.armThickness * 0.98)
            joint.segmentCount = 24
            joint.materials = [shell(Palette.line)]
            elbow.addChildNode(SCNNode(geometry: joint))

            let fore = Self.limb(thickness: Size.armThickness * 0.92,
                                 length: Size.armLength * 0.9)
            fore.materials = [shell(Palette.line)]
            let foreNode = SCNNode(geometry: fore)
            foreNode.position = SCNVector3(0, -Size.armLength * 0.45, 0)
            elbow.addChildNode(foreNode)

            // A palm with fingers on it, so an open hand and a fist are
            // different shapes rather than the same blob at two angles.
            let palm = SCNBox(width: Size.armThickness * 1.9, height: Size.armThickness * 1.5,
                              length: Size.armThickness * 1.1,
                              chamferRadius: Size.armThickness * 0.34)
            palm.chamferSegmentCount = 6
            palm.materials = [shell(Self.colour(persona.shell))]
            let handNode = SCNNode(geometry: palm)
            handNode.position = SCNVector3(0, -Size.armLength * 0.92, 0)
            elbow.addChildNode(handNode)

            var digits: [SCNNode] = []
            for finger in 0..<4 {
                let thumb = finger == 3
                let knuckle = SCNNode()
                let width = Size.armThickness * (thumb ? 0.42 : 0.36)
                let length = Size.armThickness * (thumb ? 0.62 : 0.86)
                knuckle.position = thumb
                    ? SCNVector3(side * Size.armThickness * 0.92, 0, Size.armThickness * 0.2)
                    : SCNVector3(Size.armThickness * (CGFloat(finger) - 1) * 0.58,
                                 -Size.armThickness * 0.74, 0)
                // The thumb sits across the palm rather than under it.
                if thumb { knuckle.eulerAngles.z = Self.radians(side * -70) }
                handNode.addChildNode(knuckle)

                let bone = SCNBox(width: width, height: length, length: width,
                                  chamferRadius: width * 0.42)
                bone.chamferSegmentCount = 5
                bone.materials = [shell(Self.colour(persona.shell))]
                let boneNode = SCNNode(geometry: bone)
                boneNode.position = SCNVector3(0, -length / 2, 0)
                knuckle.addChildNode(boneNode)
                digits.append(knuckle)
            }
            if side < 0 { knuckles.left = digits } else { knuckles.right = digits }
        }
    }

    private func buildLegs() {
        for (side, hip, knee) in [(CGFloat(-1), hips.left, knees.left),
                                  (CGFloat(1), hips.right, knees.right)] {
            hip.position = SCNVector3(side * Size.hipSpread, -CGFloat(Size.body.y) * 0.40, 0)
            bodyPivot.addChildNode(hip)

            // Same reason as the shoulder: the leg grows out of the body.
            let socket = SCNSphere(radius: Size.legThickness * 1.5)
            socket.segmentCount = 32
            socket.materials = [shell(Self.colour(persona.shell))]
            hip.addChildNode(SCNNode(geometry: socket))

            let thigh = Self.limb(thickness: Size.legThickness, length: Size.legLength)
            thigh.materials = [shell(Palette.line)]
            let thighNode = SCNNode(geometry: thigh)
            thighNode.position = SCNVector3(0, -Size.legLength / 2, 0)
            hip.addChildNode(thighNode)

            knee.position = SCNVector3(0, -Size.legLength, 0)
            hip.addChildNode(knee)

            let cap = SCNSphere(radius: Size.legThickness * 1.05)
            cap.segmentCount = 24
            cap.materials = [shell(Palette.line)]
            knee.addChildNode(SCNNode(geometry: cap))

            let shin = Self.limb(thickness: Size.legThickness * 0.9,
                                 length: Size.legLength * 0.9)
            shin.materials = [shell(Palette.line)]
            let shinNode = SCNNode(geometry: shin)
            shinNode.position = SCNVector3(0, -Size.legLength * 0.45, 0)
            knee.addChildNode(shinNode)

            // A foot, so it has something to plant rather than ending in a point.
            // On its own joint, so the sole can stay flat while the leg swings.
            let ankle = side < 0 ? ankles.left : ankles.right
            ankle.position = SCNVector3(0, -Size.legLength * 0.9, 0)
            knee.addChildNode(ankle)

            let foot = SCNBox(width: Size.legThickness * 2.0, height: Size.legThickness * 0.85,
                              length: Size.legThickness * 3.0,
                              chamferRadius: Size.legThickness * 0.38)
            foot.chamferSegmentCount = 6
            foot.materials = [shell(Self.colour(persona.shell))]
            let footNode = SCNNode(geometry: foot)
            footNode.position = SCNVector3(0, -Size.legThickness * 0.42, Size.legThickness * 0.55)
            ankle.addChildNode(footNode)
        }
    }

    /// The chest meter: five bars that take the badge's place while something
    /// is playing. Geometry rather than a texture, so they are crisp at any
    /// size and the bloom pass lights them like the eyes.
    private func buildMeter() {
        meter.isHidden = true
        bodyPivot.addChildNode(meter)

        let width = CGFloat(Size.body.x) * 0.075
        let gap = CGFloat(Size.body.x) * 0.042
        let span = CGFloat(Spectrum.bandCount - 1) * (width + gap)
        for band in 0..<Spectrum.bandCount {
            let bar = SCNBox(width: width, height: Self.meterHeight,
                             length: 0.028, chamferRadius: width * 0.42)
            bar.chamferSegmentCount = 6
            bar.materials = [accented()]
            // Its own pivot at the bottom, so scaling the height grows it
            // upward from a fixed baseline rather than from its middle.
            let node = SCNNode(geometry: bar)
            node.position = SCNVector3(0, Self.meterHeight / 2, 0)
            let pivot = SCNNode()
            pivot.position = SCNVector3(
                -span / 2 + CGFloat(band) * (width + gap),
                -CGFloat(Size.body.y) * 0.04,
                CGFloat(Size.body.z) * 0.47)
            pivot.addChildNode(node)
            meter.addChildNode(pivot)
            bars.append(pivot)
        }
    }

    static let meterHeight = CGFloat(0.22)

    /// The privacy light: one small lamp, in the colours macOS uses for its own
    /// dots, sat above the badge where it cannot be mistaken for decoration.
    private func buildIndicator() {
        indicator.isHidden = true
        let lamp = SCNSphere(radius: CGFloat(Size.body.x) * 0.055)
        lamp.segmentCount = 24
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = NSColor.white
        indicatorMaterial = material
        lamp.materials = [material]
        let node = SCNNode(geometry: lamp)
        indicator.addChildNode(node)
        indicator.position = SCNVector3(0, CGFloat(Size.body.y) * 0.30,
                                        CGFloat(Size.body.z) * 0.46)
        bodyPivot.addChildNode(indicator)
    }

    /// Worn only while something is playing, which is the whole signal: a pet
    /// in headphones means the machine is making noise.
    private func buildHeadphones() {
        headphones.isHidden = true
        headPivot.addChildNode(headphones)

        let band = SCNTorus(ringRadius: Size.head * 0.56, pipeRadius: Size.head * 0.045)
        band.ringSegmentCount = 48
        band.pipeSegmentCount = 16
        band.materials = [accented()]
        let bandNode = SCNNode(geometry: band)
        // Half a torus over the top, tipped back a little the way a headband
        // sits rather than balanced on the crown.
        bandNode.eulerAngles = SCNVector3(CGFloat.pi / 2, 0, 0)
        bandNode.position = SCNVector3(0, Size.head * 0.06, -Size.head * 0.06)
        headphones.addChildNode(bandNode)

        for side in [-1, 1] as [CGFloat] {
            let cup = SCNCylinder(radius: Size.head * 0.22, height: Size.head * 0.12)
            cup.radialSegmentCount = 36
            cup.materials = [shell(Palette.line, shine: 0.4)]
            let node = SCNNode(geometry: cup)
            node.eulerAngles = SCNVector3(0, 0, CGFloat.pi / 2)
            node.position = SCNVector3(side * Size.head * 0.56, -Size.head * 0.04, 0)
            headphones.addChildNode(node)

            let pad = SCNCylinder(radius: Size.head * 0.17, height: Size.head * 0.14)
            pad.radialSegmentCount = 36
            pad.materials = [accented()]
            let padNode = SCNNode(geometry: pad)
            padNode.eulerAngles = SCNVector3(0, 0, CGFloat.pi / 2)
            padNode.position = SCNVector3(side * Size.head * 0.52, -Size.head * 0.04, 0)
            headphones.addChildNode(padNode)
        }
    }

    /// A drawn shadow rather than a cast one. Shadow mapping on a transparent
    /// window puts a grey square behind everything, and this is one ellipse.
    private func buildShadow() {
        let plane = SCNPlane(width: 1.05, height: 0.58)
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = Self.shadowImage()
        material.blendMode = .alpha
        material.writesToDepthBuffer = false
        plane.materials = [material]
        shadow.geometry = plane
        shadow.eulerAngles = SCNVector3(-CGFloat.pi / 2, 0, 0)
        shadow.position = SCNVector3(0, -0.82, 0.04)
        shadow.renderingOrder = -10
        root.addChildNode(shadow)
    }

    /// A plain studio: bright above, dark below. Enough for metal to have
    /// something to reflect without shipping a cube map.
    static func studioEnvironment() -> NSImage {
        let size = NSSize(width: 8, height: 256)
        let image = NSImage(size: size)
        image.lockFocus()
        NSGradient(colors: [
            NSColor(calibratedWhite: 0.06, alpha: 1),
            NSColor(calibratedWhite: 0.42, alpha: 1),
            NSColor(calibratedWhite: 0.96, alpha: 1),
        ])?.draw(in: NSRect(origin: .zero, size: size), angle: 90)
        image.unlockFocus()
        return image
    }

    static func shadowImage() -> NSImage {
        let size = NSSize(width: 128, height: 128)
        let image = NSImage(size: size)
        image.lockFocus()
        let gradient = NSGradient(colors: [
            NSColor(calibratedWhite: 0, alpha: 0.42),
            NSColor(calibratedWhite: 0, alpha: 0),
        ])
        gradient?.draw(in: NSBezierPath(ovalIn: NSRect(origin: .zero, size: size)),
                       relativeCenterPosition: .zero)
        image.unlockFocus()
        return image
    }

    /// Shared with the dog, so the two are lit identically and a character
    /// cannot look like it came from another app.
    static func addStandardLights(to scene: SCNScene) {
        let key = SCNLight()
        key.type = .directional
        key.intensity = 1150
        key.color = NSColor(calibratedWhite: 1, alpha: 1)
        let keyNode = SCNNode()
        keyNode.light = key
        keyNode.eulerAngles = SCNVector3(-0.6, 0.7, 0)
        scene.rootNode.addChildNode(keyNode)

        // A cool rim from behind, which is what separates a dark pet from a
        // dark desktop without lightening it.
        let rim = SCNLight()
        rim.type = .directional
        rim.intensity = 820
        rim.color = Palette.brand
        let rimNode = SCNNode()
        rimNode.light = rim
        rimNode.eulerAngles = SCNVector3(0.5, -2.5, 0)
        scene.rootNode.addChildNode(rimNode)

        let fill = SCNLight()
        fill.type = .ambient
        fill.intensity = 520
        fill.color = NSColor(calibratedRed: 0.55, green: 0.66, blue: 0.74, alpha: 1)
        let fillNode = SCNNode()
        fillNode.light = fill
        scene.rootNode.addChildNode(fillNode)
    }

    /// One face painting routine for both rigs, so the two cannot drift into
    /// different faces.
    static func paint(
        _ artist: FaceArtist, into screen: SCNNode,
        context: CGContext?, texture: MTLTexture?, staging: MTLTexture?
    ) {
        guard let context, let texture, let staging else { return }
        let side = faceTextureSide
        let tall = faceTextureHeight
        let full = CGRect(x: 0, y: 0, width: CGFloat(side), height: CGFloat(tall))
        context.clear(full)
        let previous = NSGraphicsContext.current
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        // Explicit, because a context made by hand does not inherit the view
        // drawing defaults, and the eyes are all curves.
        context.setShouldAntialias(true)
        context.setAllowsAntialiasing(true)
        context.interpolationQuality = .high
        context.saveGState()
        let panel = full.insetBy(dx: full.width * 0.015, dy: full.height * 0.015)
        context.addPath(CGPath(roundedRect: panel, cornerWidth: panel.width * 0.22,
                               cornerHeight: panel.height * 0.22, transform: nil))
        context.clip()
        var flat = artist
        flat.glows = false
        let span = min(full.width, full.height) * 0.92
        flat.draw(in: CGRect(x: full.midX - span / 2, y: full.midY - span / 2,
                             width: span, height: span))
        context.restoreGState()
        NSGraphicsContext.current = previous

        guard let pixels = context.data else { return }
        let region = MTLRegionMake2D(0, 0, side, tall)
        staging.replace(region: region, mipmapLevel: 0,
                        withBytes: pixels, bytesPerRow: context.bytesPerRow)

        // The texture is larger than the visor is on screen, so it is always
        // being minified. Sampling one level of a 384 pixel image down to 150
        // aliases every curve; the mipmap chain is what makes an edge smooth.
        // The chain can only be generated into private memory, which the CPU
        // cannot write, hence the staging copy.
        guard let queue = blitQueue, let buffer = queue.makeCommandBuffer(),
              let blit = buffer.makeBlitCommandEncoder()
        else { return }
        blit.copy(from: staging, sourceSlice: 0, sourceLevel: 0,
                  sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                  sourceSize: MTLSize(width: side, height: tall, depth: 1),
                  to: texture, destinationSlice: 0, destinationLevel: 0,
                  destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
        if texture.mipmapLevelCount > 1 { blit.generateMipmaps(for: texture) }
        blit.endEncoding()
        buffer.commit()
        _ = screen
    }

    /// One queue for the mipmap pass, made once. Making one per frame is the
    /// sort of thing that quietly costs more than the work it submits.
    static let blitQueue: MTLCommandQueue? = MTLCreateSystemDefaultDevice()?.makeCommandQueue()

    static func makeFaceContext() -> CGContext? {
        CGContext(
            data: nil, width: faceTextureSide, height: faceTextureHeight,
            bitsPerComponent: 8, bytesPerRow: faceTextureSide * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                | CGBitmapInfo.byteOrder32Little.rawValue
        )
    }

    /// Texture memory the CPU can write and the GPU can copy from. A private
    /// texture is faster to sample but cannot be written directly, and a
    /// managed one cannot hold a generated mipmap chain.
    static func makeStagingTexture() -> MTLTexture? {
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm_srgb,
            width: faceTextureSide, height: faceTextureHeight, mipmapped: false)
        descriptor.usage = [.shaderRead]
        descriptor.storageMode = .managed
        return device.makeTexture(descriptor: descriptor)
    }

    static func makeFaceTexture(for screen: SCNNode) -> MTLTexture? {
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm_srgb,
            width: faceTextureSide, height: faceTextureHeight, mipmapped: true)
        // The blit pass writes the smaller levels, so the texture has to allow
        // being rendered into as well as read.
        descriptor.usage = [.shaderRead, .renderTarget]
        descriptor.storageMode = .private
        let texture = device.makeTexture(descriptor: descriptor)
        if let texture {
            let material = screen.geometry?.firstMaterial
            material?.diffuse.contents = texture
            material?.emission.contents = texture
        }
        return texture
    }

    private func buildLights() {
        let key = SCNLight()
        key.type = .directional
        key.intensity = 1150
        key.color = NSColor(calibratedWhite: 1, alpha: 1)
        let keyNode = SCNNode()
        keyNode.light = key
        keyNode.eulerAngles = SCNVector3(-0.6, 0.7, 0)
        scene.rootNode.addChildNode(keyNode)

        // A cool rim from behind, which is what separates a dark pet from a
        // dark desktop without lightening it.
        let rim = SCNLight()
        rim.type = .directional
        rim.intensity = 820
        rim.color = Palette.brand
        let rimNode = SCNNode()
        rimNode.light = rim
        rimNode.eulerAngles = SCNVector3(0.5, -2.5, 0)
        scene.rootNode.addChildNode(rimNode)

        let fill = SCNLight()
        fill.type = .ambient
        fill.intensity = 520
        fill.color = NSColor(calibratedRed: 0.55, green: 0.66, blue: 0.74, alpha: 1)
        let fillNode = SCNNode()
        fillNode.light = fill
        scene.rootNode.addChildNode(fillNode)
    }

    /// Far back with a narrow field of view: close to orthographic, so the pet
    /// does not fisheye at the edges the way a wide lens would.
    private func buildCamera() {
        let camera = SCNCamera()
        camera.fieldOfView = 27
        // Automatic reads the field of view off the shorter side, so a tall
        // window cropped the head off. The pet's height is what has to fit.
        camera.projectionDirection = .vertical
        camera.zNear = 0.1
        camera.zFar = 100
        // The eyes' glow, done on the GPU. The face texture draws them flat and
        // the bloom pass spreads the light, which is both cheaper and softer
        // than a blur recomputed on the CPU every frame.
        camera.wantsHDR = true
        camera.bloomIntensity = 1.1
        camera.bloomThreshold = 0.45
        camera.bloomBlurRadius = 14
        camera.wantsExposureAdaptation = false
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, 0.12, 6.2)
        scene.rootNode.addChildNode(cameraNode)
    }

    // MARK: - Dressing

    /// Paints every shell part one hue, for the dance. Nil puts the pet back in
    /// its own colours.
    /// The dance's rainbow, as a hue on the wheel.
    func tint(hue: Double) {
        let colour = Dance.colour(at: hue)
        tint(NSColor(calibratedHue: CGFloat(colour.hue), saturation: CGFloat(colour.saturation),
                     brightness: CGFloat(colour.brightness), alpha: 1))
    }

    func tint(_ colour: NSColor?) {
        for part in shellMaterials {
            part.material.diffuse.contents = colour ?? part.resting
        }
    }

    /// Shows the music on the chest, or puts the badge back.
    func show(_ spectrum: Spectrum?) {
        guard let spectrum, !spectrum.isSilent else {
            meter.isHidden = true
            badge.isHidden = false
            return
        }
        meter.isHidden = false
        badge.isHidden = true
        for (index, bar) in bars.enumerated() where index < spectrum.bands.count {
            // A floor, so a quiet band is still a mark rather than nothing.
            bar.scale.y = CGFloat(max(0.26, spectrum.bands[index]))
        }
    }

    /// Lights the lamp for whatever is using the microphone or the camera.
    func light(_ state: PrivacyState) {
        guard let light = state.light else {
            indicator.isHidden = true
            return
        }
        indicator.isHidden = false
        let colour = Self.colour(light.tone)
        indicatorMaterial?.diffuse.contents = colour
        // Bright enough for the bloom pass to catch, which is what makes it
        // read as a lamp rather than a painted dot.
        indicatorMaterial?.emission.contents = colour
    }

    /// What the camera looks through, for anything rendering this scene itself.
    var pointOfView: SCNNode { cameraNode }

    // MARK: - The face

    /// The screen is painted by the same artist that draws the flat face, so
    /// every expression, blink and gaze drift already works here.
    ///
    /// Into one context and one texture, both made once. Handing SceneKit a
    /// fresh CGImage per frame made it build a new texture per frame, which was
    /// most of this view's CPU; writing the same bytes into a texture it
    /// already has costs a memcpy.
    func paintFace(_ artist: FaceArtist) {
        Self.paint(artist, into: screen, context: faceContext,
                   texture: faceTexture, staging: faceStaging)
    }

    /// Comfortably more than the pixels the screen occupies: at the largest pet
    /// size the scope is about 380 device pixels on a Retina display.
    static let faceTextureSide = 384
    /// The texture is square; the visor is not. Drawing into the square and
    /// letting the plane stretch it would squash the eyes, so the face is drawn
    /// into the visor's proportions inside the square and the rest is clear.
    static var faceTextureHeight: Int {
        Int((Double(faceTextureSide) * Size.visor.height / Size.visor.width).rounded())
    }

    private lazy var faceStaging: MTLTexture? = Self.makeStagingTexture()

    private lazy var faceContext: CGContext? = {
        let side = Self.faceTextureSide
        // BGRA to match the texture it is copied into, so the upload is a
        // straight memcpy with no swizzle.
        return CGContext(
            data: nil, width: side, height: Self.faceTextureHeight,
            bitsPerComponent: 8, bytesPerRow: side * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                | CGBitmapInfo.byteOrder32Little.rawValue
        )
    }()

    private lazy var faceTexture: MTLTexture? = {
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm_srgb,
            width: Self.faceTextureSide, height: Self.faceTextureHeight, mipmapped: false)
        descriptor.usage = [.shaderRead]
        descriptor.storageMode = .managed
        let texture = device.makeTexture(descriptor: descriptor)
        if let texture {
            let material = screen.geometry?.firstMaterial
            material?.diffuse.contents = texture
            material?.emission.contents = texture
        }
        return texture
    }()

}
