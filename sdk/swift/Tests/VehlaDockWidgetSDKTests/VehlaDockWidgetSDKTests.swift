import AppKit
import Testing
@testable import VehlaDockWidgetSDK

@Test
func descriptorProvidesSafeCompactDefaults() {
    let descriptor = VehlaDockWidgetDescriptor(
        id: "status",
        title: "Status"
    )

    #expect(descriptor.systemImage == "shippingbox")
    #expect(descriptor.preferredPopupWidth == 420)
    #expect(descriptor.preferredPopupHeight == 520)
    #expect(descriptor.supportedSurfaces == [.compact])
    #expect(descriptor.supportsSurface(.compact))
    #expect(!descriptor.supportsSurface(.popup))
}

@Test
func descriptorCarriesAllPresentationMetadata() {
    let descriptor = VehlaDockWidgetDescriptor(
        id: "builds",
        title: "Builds",
        subtitle: "Latest status",
        systemImage: "hammer",
        preferredPopupWidth: 560,
        preferredPopupHeight: 640,
        supportedSurfaces: [.compact, .inline, .popup]
    )

    #expect(descriptor.subtitle == "Latest status")
    #expect(descriptor.supportedSurfaces == [.compact, .inline, .popup])
}

@Test
func dockWidgetThemeProvidesCompatibleTileColors() {
    let compatibleTheme = VehlaDockWidgetTheme(
        isDark: true,
        accentColor: .systemBlue,
        primaryTextColor: .labelColor,
        secondaryTextColor: .secondaryLabelColor,
        surfaceColor: .windowBackgroundColor
    )
    #expect(compatibleTheme.tileTextColor == .labelColor)

    let explicitTheme = VehlaDockWidgetTheme(
        isDark: true,
        accentColor: .systemBlue,
        primaryTextColor: .labelColor,
        secondaryTextColor: .secondaryLabelColor,
        tileTextColor: .systemYellow,
        surfaceColor: .windowBackgroundColor
    )
    #expect(explicitTheme.tileTextColor == .systemYellow)
}

@Test
func contextInvalidatesAndBrokersActions() throws {
    var invalidationCount = 0
    var actions: [VehlaDockWidgetAction] = []
    var storedSecret: (id: String, value: String)?
    var removedSecretID: String?
    let context = VehlaDockWidgetContext(
        packageID: "com.example.widgets",
        widgetID: "builds",
        dataDirectory: URL(fileURLWithPath: "/tmp/widgets"),
        theme: VehlaDockWidgetTheme(
            isDark: true,
            accentColor: .systemBlue,
            primaryTextColor: .labelColor,
            secondaryTextColor: .secondaryLabelColor,
            surfaceColor: .windowBackgroundColor
        ),
        secretLookup: { $0 == "apiKey" ? "secret" : nil },
        secretStore: { id, value in
            storedSecret = (id, value)
        },
        secretRemove: { removedSecretID = $0 },
        invalidationHandler: { invalidationCount += 1 },
        actionHandler: { actions.append($0) }
    )

    #expect(context.secret(named: "apiKey") == "secret")
    try context.setSecret("replacement", named: "apiKey")
    #expect(storedSecret?.id == "apiKey")
    #expect(storedSecret?.value == "replacement")
    try context.removeSecret(named: "apiKey")
    #expect(removedSecretID == "apiKey")
    context.invalidate()
    context.copyText("green")
    context.open(URL(string: "https://example.com")!)
    context.showMessage("Ready")
    context.notify(title: "Build", body: "Passed")

    #expect(invalidationCount == 1)
    #expect(actions.count == 4)
    guard case .copyText("green") = actions[0],
          case .openURL(let url) = actions[1],
          case .showMessage("Ready") = actions[2],
          case .notify("Build", "Passed") = actions[3] else {
        Issue.record("Context emitted unexpected brokered actions")
        return
    }
    #expect(url.absoluteString == "https://example.com")
}

@Test
@MainActor
func localAIBridgeForwardsStatusAndCompletion() async throws {
    var received: [VehlaDockWidgetAIMessage] = []
    let bridge = VehlaDockWidgetLocalAIBridge(
        availabilityHandler: { true },
        statusHandler: { "Local · Test Model" },
        completionHandler: { messages in
            received = messages
            return "Local response"
        }
    )

    #expect(bridge.isAvailable)
    #expect(bridge.statusLabel == "Local · Test Model")
    let response = try await bridge.complete(
        messages: [
            VehlaDockWidgetAIMessage(role: .system, content: "Be concise."),
            VehlaDockWidgetAIMessage(role: .user, content: "Hello"),
        ]
    )

    #expect(response == "Local response")
    #expect(received.count == 2)
    #expect(received.last?.role == .user)
}

@Test
@MainActor
func clipboardBridgeForwardsHistoryAndMutations() {
    let item = VehlaDockWidgetClipboardItem(
        id: "clip-1",
        kind: .url,
        text: "https://example.com",
        preview: "Example",
        searchText: "example",
        imageFileURL: nil,
        createdAt: Date(),
        sourceAppName: "Safari",
        isPinned: true
    )
    var restoredID: String?
    var deletedID: String?
    var cleared = false
    var pinRequest: (String, Bool)?
    var activeViewer = false
    let bridge = VehlaDockWidgetClipboardBridge(
        itemCountHandler: { 1 },
        itemsHandler: { offset, limit in
            offset == 0 && limit > 0 ? [item] : []
        },
        restoreHandler: {
            restoredID = $0
            return true
        },
        deleteHandler: { deletedID = $0 },
        clearHandler: { cleared = true },
        pinHandler: {
            pinRequest = ($0, $1)
            return $1
        },
        activeViewerHandler: { activeViewer = $0 }
    )

    #expect(bridge.totalItemCount == 1)
    #expect(bridge.items(offset: 0, limit: 20).first?.kind == .url)
    #expect(bridge.items(offset: 1, limit: 20).isEmpty)
    #expect(bridge.restoreItem(id: item.id))
    bridge.deleteItem(id: item.id)
    bridge.clearHistory()
    #expect(bridge.setPinned(false, itemID: item.id) == false)
    bridge.setActiveViewer(true)

    #expect(restoredID == item.id)
    #expect(deletedID == item.id)
    #expect(cleared)
    #expect(pinRequest?.0 == item.id)
    #expect(pinRequest?.1 == false)
    #expect(activeViewer)
}

@Test
@MainActor
func appBridgePublishesContextAndDispatchesActions() {
    let entity = VehlaDockWidgetSharedContext(
        id: "event-1",
        kind: .event,
        sourceID: "calendar",
        title: "Design review"
    )
    var published: VehlaDockWidgetSharedContext?
    var dispatched: VehlaDockWidgetSharedAction?
    var timerDuration: TimeInterval?
    let bridge = VehlaDockWidgetAppBridge(
        currentContextHandler: { entity },
        publishHandler: {
            published = $0
            return true
        },
        actionHandler: { action, _ in
            dispatched = action
            return true
        },
        timerHandler: { _, duration, _ in
            timerDuration = duration
            return true
        }
    )

    #expect(bridge.currentContext?.title == "Design review")
    #expect(bridge.publish(entity))
    #expect(published?.id == entity.id)
    #expect(bridge.perform(.askAI, with: entity))
    #expect(dispatched == .askAI)
    #expect(bridge.startTimer(label: "Review", duration: 300))
    #expect(timerDuration == 300)
}
