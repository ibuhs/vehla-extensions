import Foundation

public enum ToggleID: String, Codable, CaseIterable, Sendable {
    case darkMode, keepAwake, mute, desktopIcons

    public var title: String {
        switch self {
        case .darkMode: return "Dark Mode"
        case .keepAwake: return "Keep Awake"
        case .mute: return "Mute"
        case .desktopIcons: return "Desktop Icons"
        }
    }

    public var systemImage: String {
        switch self {
        case .darkMode: return "moon.fill"
        case .keepAwake: return "cup.and.saucer.fill"
        case .mute: return "speaker.slash.fill"
        case .desktopIcons: return "menubar.dock.rectangle"
        }
    }
}

public struct AppEntry: Codable, Equatable, Sendable, Identifiable {
    public var name: String
    public var id: String { name }
    public init(name: String) { self.name = name }
}

/// One step of a scene.
public enum Step: Codable, Equatable, Sendable {
    case shortcut(String)
    case app(String)
    case toggle(ToggleID, on: Bool)
    case url(String)
    case wait(Double)

    enum Keys: String, CodingKey { case type, name, id, on, url, seconds }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        switch try c.decode(String.self, forKey: .type) {
        case "shortcut": self = .shortcut(try c.decode(String.self, forKey: .name))
        case "app": self = .app(try c.decode(String.self, forKey: .name))
        case "toggle": self = .toggle(try c.decode(ToggleID.self, forKey: .id), on: try c.decode(Bool.self, forKey: .on))
        case "url": self = .url(try c.decode(String.self, forKey: .url))
        case "wait": self = .wait(try c.decode(Double.self, forKey: .seconds))
        case let other:
            throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "Unknown step type \(other)")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        switch self {
        case .shortcut(let n): try c.encode("shortcut", forKey: .type); try c.encode(n, forKey: .name)
        case .app(let n): try c.encode("app", forKey: .type); try c.encode(n, forKey: .name)
        case .toggle(let id, let on): try c.encode("toggle", forKey: .type); try c.encode(id, forKey: .id); try c.encode(on, forKey: .on)
        case .url(let u): try c.encode("url", forKey: .type); try c.encode(u, forKey: .url)
        case .wait(let s): try c.encode("wait", forKey: .type); try c.encode(s, forKey: .seconds)
        }
    }

    public var summary: String {
        switch self {
        case .shortcut(let n): return "Shortcut: \(n)"
        case .app(let n): return "Open \(n)"
        case .toggle(let id, let on): return "\(id.title) \(on ? "on" : "off")"
        case .url(let u): return "Open \(u)"
        case .wait(let s): return "Wait \(Int(s))s"
        }
    }
}

public struct ActionScene: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var icon: String
    public var steps: [Step]

    public init(id: String, name: String, icon: String, steps: [Step]) {
        self.id = id; self.name = name; self.icon = icon; self.steps = steps
    }
}

public struct ActionsConfig: Codable, Equatable, Sendable {
    public var scenes: [ActionScene]
    public var apps: [AppEntry]
    public var toggles: [ToggleID]

    public init(scenes: [ActionScene], apps: [AppEntry], toggles: [ToggleID]) {
        self.scenes = scenes; self.apps = apps; self.toggles = toggles
    }

    public static let `default` = ActionsConfig(
        scenes: [
            ActionScene(id: "focus", name: "Focus", icon: "moon.stars.fill",
                        steps: [.toggle(.darkMode, on: true), .toggle(.mute, on: true), .toggle(.keepAwake, on: true)]),
            ActionScene(id: "wind-down", name: "Wind Down", icon: "bed.double.fill",
                        steps: [.toggle(.keepAwake, on: false), .toggle(.mute, on: false), .toggle(.darkMode, on: true)]),
            ActionScene(id: "present", name: "Present", icon: "rectangle.on.rectangle",
                        steps: [.toggle(.desktopIcons, on: false), .toggle(.mute, on: true), .toggle(.keepAwake, on: true)]),
        ],
        apps: ["Safari", "Notes", "Terminal", "System Settings"].map(AppEntry.init),
        toggles: ToggleID.allCases
    )
}
