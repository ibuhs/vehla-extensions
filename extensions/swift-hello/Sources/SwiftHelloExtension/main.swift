import AppKit
import Foundation
import VehlaStoreSDK

enum SwiftHelloError: LocalizedError {
    case missingName
    case unknownCommand(String)

    var errorDescription: String? {
        switch self {
        case .missingName:
            return "Enter a name before running the greeting."
        case .unknownCommand(let command):
            return "Unknown Swift command: \(command)"
        }
    }
}

@main
struct SwiftHelloExtension {
    static func main() async {
        await runStoreExtension { invocation in
            switch invocation.commandID {
            case "greet":
                return try greeting(for: invocation)
            case "runtime":
                return await runtimeDetails()
            default:
                throw SwiftHelloError.unknownCommand(
                    invocation.commandID
                )
            }
        }
    }

    private static func greeting(
        for invocation: StoreInvocation
    ) throws -> StoreResult {
        guard let name = invocation.context.formValues["name"]?
            .stringValue?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty else {
            throw SwiftHelloError.missingName
        }

        let message = "Hello, \(name), from a native Swift extension."
        let view = StoreRichView(
            title: "Swift says hello",
            subtitle: "Executed outside the Vehla process",
            sections: [
                StoreRichSection(
                    title: "Greeting",
                    items: [
                        .text(message),
                        .detail(
                            "Executable",
                            value: CommandLine.arguments[0]
                        ),
                    ]
                ),
            ],
            actions: [
                StoreAction(
                    type: .copyText,
                    value: message,
                    label: "Copy Greeting",
                    systemImage: "doc.on.doc"
                ),
            ]
        )
        let notification = invocation.context.formValues["notify"]?
            .boolValue == true
            ? StoreAction(
                type: .notify,
                value: message,
                title: "Swift extension completed"
            )
            : nil
        return StoreResult(action: notification, view: view)
    }

    private static func runtimeDetails() async -> StoreResult {
        let process = ProcessInfo.processInfo
        let activationIsProhibited = await MainActor.run {
            NSApplication.shared.activationPolicy() == .prohibited
        }
        let backgroundEnvironmentIsSet =
            process.environment["VEHLA_EXTENSION_BACKGROUND"] == "1"
        return Store.view(
            StoreRichView(
                title: "Swift Runtime",
                subtitle: "Native executable diagnostics",
                sections: [
                    StoreRichSection(
                        items: [
                            .detail("Process ID", value: "\(process.processIdentifier)"),
                            .detail("Operating system", value: process.operatingSystemVersionString),
                            .detail("Processors", value: "\(process.processorCount)"),
                            .detail("Architecture", value: architecture),
                            .detail(
                                "App activation",
                                value: activationIsProhibited ? "Prohibited" : "Allowed"
                            ),
                            .detail(
                                "Background environment",
                                value: backgroundEnvironmentIsSet ? "Enabled" : "Missing"
                            ),
                            .detail("Swift", value: "Compiled native executable"),
                        ]
                    ),
                ]
            )
        )
    }

    private static var architecture: String {
#if arch(arm64)
        "arm64"
#else
        "unsupported"
#endif
    }
}
