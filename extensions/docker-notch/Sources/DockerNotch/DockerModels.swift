import Foundation

/// One container, from a line of `docker ps -a --format '{{json .}}'`.
struct DockerContainer: Identifiable, Equatable, Sendable {
    var id: String
    var name: String
    var image: String
    /// running, exited, paused, restarting, created, dead.
    var state: String
    /// Docker's own words: "Up 3 hours", "Exited (1) 2 minutes ago".
    var status: String

    var isRunning: Bool { state == "running" || state == "restarting" }
}

/// What a line of `docker events --format '{{json .}}'` says about a container.
struct DockerEvent: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case started
        case died(exitCode: Int)
        case unhealthy
        /// Created, destroyed, renamed, paused: the list changed, nothing to announce.
        case changed
    }

    var kind: Kind
    var id: String
    var name: String
}

/// When a stopped container is announced in the closed Notch.
enum DockerAlerts: String, CaseIterable, Sendable {
    case all, failures, off

    var title: String {
        switch self {
        case .all: "Any stop"
        case .failures: "Failures only"
        case .off: "Off"
        }
    }

    var next: DockerAlerts {
        let all = Self.allCases
        return all[(all.firstIndex(of: self)! + 1) % all.count]
    }

    /// Whether a container ending with this exit code is worth saying.
    func announces(exitCode: Int) -> Bool {
        switch self {
        case .all: true
        case .failures: exitCode != 0
        case .off: false
        }
    }
}

enum DockerParser {
    /// Every container in `docker ps` output, running ones first, then by name.
    static func containers(_ output: String) -> [DockerContainer] {
        output.split(whereSeparator: \.isNewline).compactMap { line -> DockerContainer? in
            guard let fields = object(String(line)), let id = fields["ID"] as? String, !id.isEmpty else { return nil }
            // A container can have several names; the first is the one Docker shows.
            let name = (fields["Names"] as? String ?? "").split(separator: ",").first.map(String.init) ?? id
            return DockerContainer(id: id, name: name, image: fields["Image"] as? String ?? "",
                                   state: (fields["State"] as? String ?? "").lowercased(), status: fields["Status"] as? String ?? "")
        }
        .sorted { ($0.isRunning ? 0 : 1, $0.name.lowercased()) < ($1.isRunning ? 0 : 1, $1.name.lowercased()) }
    }

    /// Nil for lines that aren't about a container or that change nothing shown (exec, attach, top…).
    static func event(_ line: String) -> DockerEvent? {
        guard let fields = object(line), (fields["Type"] as? String ?? "container") == "container",
              let action = (fields["Action"] as? String ?? fields["status"] as? String)?.lowercased() else { return nil }
        let actor = fields["Actor"] as? [String: Any]
        let attributes = actor?["Attributes"] as? [String: Any] ?? [:]
        let id = String((actor?["ID"] as? String ?? fields["id"] as? String ?? "").prefix(12))
        guard !id.isEmpty else { return nil }
        let name = attributes["name"] as? String ?? id
        let kind: DockerEvent.Kind
        switch action {
        case "start": kind = .started
        case "die": kind = .died(exitCode: Int(attributes["exitCode"] as? String ?? "") ?? 0)
        case "health_status: unhealthy": kind = .unhealthy
        case "create", "destroy", "rename", "pause", "unpause", "stop", "kill", "restart", "health_status: healthy": kind = .changed
        default: return nil
        }
        return DockerEvent(kind: kind, id: id, name: name)
    }

    /// "3 running · 2 stopped".
    static func summary(_ containers: [DockerContainer]) -> String {
        let running = containers.filter(\.isRunning).count
        let stopped = containers.count - running
        if containers.isEmpty { return "No containers" }
        return stopped == 0 ? "\(running) running" : "\(running) running · \(stopped) stopped"
    }

    private static func object(_ line: String) -> [String: Any]? {
        guard let data = line.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}
