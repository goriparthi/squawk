import Foundation

/// Whether anything on the machine is listening or watching. The pet wears this
/// the way macOS wears its own dots, in the same colours, because a second
/// convention for the same fact would be worse than none.
public struct PrivacyState: Sendable, Equatable {
    public var microphone: Bool
    public var camera: Bool

    public init(microphone: Bool = false, camera: Bool = false) {
        self.microphone = microphone
        self.camera = camera
    }

    public static let clear = PrivacyState()

    public var isClear: Bool { !microphone && !camera }

    /// What the indicator shows. The camera wins when both are on, which is
    /// what macOS does: a camera implies a microphone far more often than the
    /// other way round, and the greater exposure is the one worth naming.
    public var light: Light? {
        if camera { return .camera }
        if microphone { return .microphone }
        return nil
    }

    public enum Light: Sendable, Equatable {
        case microphone
        case camera

        /// Apple's own colours. Orange for listening, green for watching.
        public var tone: Tone {
            switch self {
            case .microphone: Tone(hex: 0xFF9F0A)
            case .camera: Tone(hex: 0x30D158)
            }
        }

        public var label: String {
            switch self {
            case .microphone: "Microphone in use"
            case .camera: "Camera in use"
            }
        }
    }
}
