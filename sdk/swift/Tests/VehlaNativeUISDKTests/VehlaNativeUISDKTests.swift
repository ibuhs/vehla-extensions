import AppKit
import Testing
@testable import VehlaNativeUISDK

@Test
func descriptorCarriesWorkspacePresentationMetadata() {
    let descriptor = VehlaWorkspaceDescriptor(
        id: "postr",
        title: "PoStr",
        systemImage: "network",
        preferredWidth: 1_200,
        preferredHeight: 800
    )

    #expect(descriptor.id == "postr")
    #expect(descriptor.preferredWidth == 1_200)
    #expect(descriptor.dismissBehavior == .persistent)
}

@Test
func quickGlassDescriptorUsesBackwardCompatibleDefaults() {
    let descriptor = VehlaWorkspaceQuickGlassActionDescriptor(
        id: "format-json",
        title: "Format JSON"
    )

    #expect(VehlaNativeUIAPIVersion == 1)
    #expect(descriptor.id == "format-json")
    #expect(descriptor.systemImage == "sparkles")
    #expect(descriptor.delivery == .compactResult)
}

@Test
func quickGlassRequestAndResultCarryInvocationMetadata() {
    let request = VehlaWorkspaceQuickGlassRequest(
        actionID: "format-json",
        selectedText: #"{"name":"Vehla"}"#,
        isEditable: true,
        frontAppName: "TextEdit",
        payload: ["source": "quickGlass"]
    )
    let result = VehlaWorkspaceQuickGlassResult(
        outputText: """
        {
          "name": "Vehla"
        }
        """,
        delivery: .replaceSelection
    )

    #expect(request.actionID == "format-json")
    #expect(request.isEditable)
    #expect(request.frontAppName == "TextEdit")
    #expect(request.payload["source"] == "quickGlass")
    #expect(result.outputText?.contains(#""name": "Vehla""#) == true)
    #expect(result.errorMessage == nil)
    #expect(result.delivery == .replaceSelection)
}

@Test
func contextBrokersSecretsAndActions() throws {
    var action: VehlaWorkspaceAction?
    var storedSecret: (id: String, value: String)?
    let context = VehlaWorkspaceContext(
        packageID: "com.vehla.postr",
        workspaceID: "postr",
        dataDirectory: URL(fileURLWithPath: "/tmp/postr"),
        launchRequest: VehlaWorkspaceLaunchRequest(),
        theme: VehlaWorkspaceTheme(
            isDark: true,
            accentColor: .systemBlue,
            primaryTextColor: .labelColor,
            secondaryTextColor: .secondaryLabelColor,
            surfaceColor: .windowBackgroundColor
        ),
        secretLookup: { $0 == "postmanAPIKey" ? "secret" : nil },
        secretStore: { id, value in
            storedSecret = (id, value)
        },
        actionHandler: { action = $0 }
    )

    #expect(context.secret(named: "postmanAPIKey") == "secret")
    try context.setSecret("replacement", named: "postmanAPIKey")
    #expect(storedSecret?.id == "postmanAPIKey")
    #expect(storedSecret?.value == "replacement")
    context.copyText("copied")

    guard case .copyText(let value) = action else {
        Issue.record("Expected a copy action")
        return
    }
    #expect(value == "copied")
}

@Test
@MainActor
func localAIBridgeForwardsStatusAndCompletion() async throws {
    var received: [VehlaWorkspaceAIMessage] = []
    let bridge = VehlaWorkspaceLocalAIBridge(
        availabilityHandler: { true },
        statusHandler: { "Local · Test Model" },
        completionHandler: { messages in
            received = messages
            return "Generated locally"
        }
    )
    let messages = [
        VehlaWorkspaceAIMessage(role: .system, content: "Be concise."),
        VehlaWorkspaceAIMessage(role: .user, content: "Hello"),
    ]

    #expect(bridge.isAvailable)
    #expect(bridge.statusLabel == "Local · Test Model")
    #expect(try await bridge.complete(messages: messages) == "Generated locally")
    #expect(received == messages)
}
