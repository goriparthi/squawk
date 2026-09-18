import XCTest
@testable import SquawkCore

final class PrivacyStateTests: XCTestCase {
    func testNothingInUseShowsNothing() {
        XCTAssertTrue(PrivacyState.clear.isClear)
        XCTAssertNil(PrivacyState.clear.light)
    }

    func testTheMicrophoneIsOrangeAndTheCameraIsGreen() {
        XCTAssertEqual(PrivacyState(microphone: true).light, .microphone)
        XCTAssertEqual(PrivacyState(camera: true).light, .camera)
        // The same colours macOS uses for its own dots, so the pet is not
        // inventing a second language for the same fact.
        XCTAssertEqual(PrivacyState.Light.microphone.tone, Tone(hex: 0xFF9F0A))
        XCTAssertEqual(PrivacyState.Light.camera.tone, Tone(hex: 0x30D158))
    }

    /// Both at once is a call, and the camera is the greater exposure.
    func testTheCameraWinsWhenBothAreOn() {
        let onACall = PrivacyState(microphone: true, camera: true)
        XCTAssertEqual(onACall.light, .camera)
        XCTAssertFalse(onACall.isClear)
    }
}
