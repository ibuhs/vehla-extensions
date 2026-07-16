#!/usr/bin/env swift

import CryptoKit
import Foundation

enum SigningError: Error, CustomStringConvertible {
    case usage
    case missingPrivateKey
    case invalidPrivateKey
    case unreadableArchive

    var description: String {
        switch self {
        case .usage:
            return "Usage: publisher-signing.swift generate | public-key | sign <archive>"
        case .missingPrivateKey:
            return "VEHLA_PUBLISHER_PRIVATE_KEY is required."
        case .invalidPrivateKey:
            return "VEHLA_PUBLISHER_PRIVATE_KEY must be a base64-encoded Ed25519 private key."
        case .unreadableArchive:
            return "The archive could not be read."
        }
    }
}

func privateKeyFromEnvironment() throws -> Curve25519.Signing.PrivateKey {
    guard let encoded = ProcessInfo.processInfo.environment[
        "VEHLA_PUBLISHER_PRIVATE_KEY"
    ] else {
        throw SigningError.missingPrivateKey
    }
    guard let data = Data(base64Encoded: encoded),
          let key = try? Curve25519.Signing.PrivateKey(
            rawRepresentation: data
          ) else {
        throw SigningError.invalidPrivateKey
    }
    return key
}

do {
    guard CommandLine.arguments.count >= 2 else {
        throw SigningError.usage
    }
    switch CommandLine.arguments[1] {
    case "generate":
        let key = Curve25519.Signing.PrivateKey()
        let output = [
            "privateKey": key.rawRepresentation.base64EncodedString(),
            "publicKey": key.publicKey.rawRepresentation.base64EncodedString(),
        ]
        let data = try JSONSerialization.data(
            withJSONObject: output,
            options: [.prettyPrinted, .sortedKeys]
        )
        print(String(decoding: data, as: UTF8.self))
    case "public-key":
        let key = try privateKeyFromEnvironment()
        print(key.publicKey.rawRepresentation.base64EncodedString())
    case "sign":
        guard CommandLine.arguments.count == 3 else {
            throw SigningError.usage
        }
        let key = try privateKeyFromEnvironment()
        guard let archive = FileManager.default.contents(
            atPath: CommandLine.arguments[2]
        ) else {
            throw SigningError.unreadableArchive
        }
        print(try key.signature(for: archive).base64EncodedString())
    default:
        throw SigningError.usage
    }
} catch {
    FileHandle.standardError.write(Data("\(error)\n".utf8))
    exit(1)
}
