import Foundation
import CryptoKit

func generateSignature(for fileURL: URL) -> String? {
    do {
        let fileData = try Data(contentsOf: fileURL)
        
        // Generate a new key pair
        let privateKey = Curve25519.Signing.PrivateKey()
        let signature = try privateKey.signature(for: fileData)
        
        // Convert signature to base64
        let signatureBase64 = signature.base64EncodedString()
        
        // Print both the signature and the public key
        print("Signature (base64): \(signatureBase64)")
        print("Public key (base64): \(privateKey.publicKey.rawRepresentation.base64EncodedString())")
        
        return signatureBase64
    } catch {
        print("Error: \(error)")
        return nil
    }
}

// Main
guard CommandLine.arguments.count > 1 else {
    print("Usage: sign_update <file>")
    exit(1)
}

let filePath = CommandLine.arguments[1]
let fileURL = URL(fileURLWithPath: filePath)

if let signature = generateSignature(for: fileURL) {
    print(signature)
    exit(0)
} else {
    print("Failed to generate signature")
    exit(1)
} 
