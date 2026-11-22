import XCTest
@testable import DockerNotch

final class DockerNotchTests: XCTestCase {
    func testContainersAreReadAndSorted() {
        let output = """
        {"ID":"bbb222","Names":"zeta","Image":"redis:7","State":"exited","Status":"Exited (1) 2 minutes ago"}
        {"ID":"aaa111","Names":"web,web-alias","Image":"nginx","State":"running","Status":"Up 3 hours"}
        not json
        {"Names":"no id"}
        {"ID":"ccc333","Names":"Alpha","Image":"postgres","State":"running","Status":"Up 1 minute"}
        """
        let containers = DockerParser.containers(output)
        XCTAssertEqual(containers.map(\.name), ["Alpha", "web", "zeta"])
        XCTAssertEqual(containers.map(\.isRunning), [true, true, false])
        XCTAssertEqual(DockerParser.summary(containers), "2 running · 1 stopped")
        XCTAssertEqual(DockerParser.summary([]), "No containers")
        XCTAssertEqual(DockerParser.summary(Array(containers.prefix(2))), "2 running")
    }

    func testEvents() {
        let die = #"{"status":"die","id":"0123456789abcdef","Type":"container","Action":"die","Actor":{"ID":"0123456789abcdef","Attributes":{"exitCode":"137","image":"nginx","name":"web"}}}"#
        XCTAssertEqual(DockerParser.event(die), DockerEvent(kind: .died(exitCode: 137), id: "0123456789ab", name: "web"))
        let start = #"{"Type":"container","Action":"start","Actor":{"ID":"0123456789abcdef","Attributes":{"name":"web"}}}"#
        XCTAssertEqual(DockerParser.event(start)?.kind, .started)
        let unhealthy = #"{"Type":"container","Action":"health_status: unhealthy","Actor":{"ID":"0123456789abcdef","Attributes":{"name":"db"}}}"#
        XCTAssertEqual(DockerParser.event(unhealthy)?.kind, .unhealthy)
        let exec = #"{"Type":"container","Action":"exec_start: sh","Actor":{"ID":"0123456789abcdef","Attributes":{"name":"db"}}}"#
        XCTAssertNil(DockerParser.event(exec))
        let network = #"{"Type":"network","Action":"connect","Actor":{"ID":"0123456789abcdef","Attributes":{}}}"#
        XCTAssertNil(DockerParser.event(network))
        XCTAssertNil(DockerParser.event("garbage"))
    }

    func testAlerts() {
        XCTAssertTrue(DockerAlerts.all.announces(exitCode: 0))
        XCTAssertFalse(DockerAlerts.failures.announces(exitCode: 0))
        XCTAssertTrue(DockerAlerts.failures.announces(exitCode: 1))
        XCTAssertFalse(DockerAlerts.off.announces(exitCode: 1))
        XCTAssertEqual(DockerAlerts.all.next.next.next, .all)
    }
}
