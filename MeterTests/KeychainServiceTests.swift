import XCTest
@testable import Meter

final class KeychainServiceTests: XCTestCase {
    func test_parseToken_validPayload_returnsAccessToken() throws {
        let data = TestFixtures.data(named: "keychain_credential.json")
        let token = try KeychainService.parseToken(from: data)
        XCTAssertEqual(token, "sk-ant-oat01-fixture-token-value")
    }

    func test_parseToken_malformedTopLevel_throwsUnexpectedFormat() {
        let data = TestFixtures.data(named: "keychain_credential_malformed.json")
        XCTAssertThrowsError(try KeychainService.parseToken(from: data)) { error in
            XCTAssertEqual(error as? KeychainError, .unexpectedFormat)
        }
    }

    func test_parseToken_emptyToken_throwsUnexpectedFormat() {
        let json = #"{"claudeAiOauth": {"accessToken": ""}}"#
        XCTAssertThrowsError(
            try KeychainService.parseToken(from: Data(json.utf8))
        ) { error in
            XCTAssertEqual(error as? KeychainError, .unexpectedFormat)
        }
    }

    func test_parseToken_notJSON_throwsUnexpectedFormat() {
        XCTAssertThrowsError(
            try KeychainService.parseToken(from: Data("garbage".utf8))
        ) { error in
            XCTAssertEqual(error as? KeychainError, .unexpectedFormat)
        }
    }

    func test_keychainError_equality() {
        XCTAssertEqual(KeychainError.itemNotFound, KeychainError.itemNotFound)
        XCTAssertNotEqual(KeychainError.itemNotFound, KeychainError.unexpectedFormat)
        XCTAssertEqual(KeychainError.unhandled(-25300), KeychainError.unhandled(-25300))
        XCTAssertNotEqual(KeychainError.unhandled(-25300), KeychainError.unhandled(-1))
    }
}
