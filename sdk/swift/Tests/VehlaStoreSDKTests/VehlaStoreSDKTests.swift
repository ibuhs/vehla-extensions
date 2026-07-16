import Foundation
import Testing
@testable import VehlaStoreSDK

@Test
func decodesInvocationContext() throws {
    let data = Data(
        """
        {
          "packageID": "com.example.swift",
          "commandID": "inspect",
          "query": "hello",
          "context": {
            "secrets": {"token": "value"},
            "formValues": {
              "enabled": true,
              "name": "Vehla",
              "file": {
                "path": "/tmp/example.txt",
                "name": "example.txt",
                "isDirectory": false,
                "size": 42
              }
            }
          }
        }
        """.utf8
    )
    let invocation = try JSONDecoder().decode(
        StoreInvocation.self,
        from: data
    )

    #expect(invocation.commandID == "inspect")
    #expect(invocation.context.secrets["token"] == "value")
    #expect(invocation.context.formValues["enabled"]?.boolValue == true)
    #expect(invocation.context.formValues["name"]?.stringValue == "Vehla")
    #expect(
        invocation.context.formValues["file"]?.fileValue?.name
            == "example.txt"
    )
}

@Test
func encodesRichResultWireFormat() throws {
    let result = Store.view(
        StoreRichView(
            title: "Swift result",
            sections: [
                StoreRichSection(
                    title: "Details",
                    items: [
                        .detail("Runtime", value: "Swift"),
                        .code("let value = 1", language: "swift"),
                    ]
                ),
            ],
            actions: [
                StoreAction(
                    type: .copyText,
                    value: "Copied",
                    label: "Copy"
                ),
            ]
        )
    )
    let object = try #require(
        JSONSerialization.jsonObject(
            with: JSONEncoder().encode(result)
        ) as? [String: Any]
    )
    let view = try #require(object["view"] as? [String: Any])
    let sections = try #require(view["sections"] as? [[String: Any]])
    let actions = try #require(view["actions"] as? [[String: Any]])

    #expect(view["title"] as? String == "Swift result")
    #expect(sections.first?["title"] as? String == "Details")
    #expect(actions.first?["type"] as? String == "copyText")
}
