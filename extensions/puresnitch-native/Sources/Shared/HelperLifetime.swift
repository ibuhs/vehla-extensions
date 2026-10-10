/// A successful idle exit is safe only when no client or enforcing runtime
/// needs this process. launchd keeps the Mach service registered for reopening.
enum HelperLifetime {
    static func canExit(hasClients: Bool, enforcementDesired: Bool, migrationPending: Bool,
                        pfActive: Bool, dnsActive: Bool) -> Bool {
        !hasClients && !enforcementDesired && !migrationPending && !pfActive && !dnsActive
    }
}
