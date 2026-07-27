import Foundation

actor PreferencesStore {
    private let url: URL

    init(directory: URL) {
        url = directory.appendingPathComponent("toolbox-preferences.json", isDirectory: false)
    }

    func loadSelectedToolID() -> String? {
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = object["selectedToolID"] as? String
        else {
            return nil
        }
        return id
    }

    func saveSelectedToolID(_ id: String) {
        let payload: [String: Any] = ["selectedToolID": id]
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted]) else {
            return
        }
        try? data.write(to: url, options: .atomic)
    }
}
