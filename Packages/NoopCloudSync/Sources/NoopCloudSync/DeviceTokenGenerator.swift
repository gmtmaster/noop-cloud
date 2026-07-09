import Foundation
import Security

public enum DeviceTokenGenerator {
    public static func makeToken(byteCount: Int = 32) throws -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        let status = SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes)
        guard status == errSecSuccess else {
            throw DeviceTokenGeneratorError.randomGenerationFailed(status)
        }

        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

public enum DeviceTokenGeneratorError: Error, Equatable, Sendable {
    case randomGenerationFailed(OSStatus)
}
