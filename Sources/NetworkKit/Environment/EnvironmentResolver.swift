import Foundation

/// Supplies the environment used for each request.
///
/// Resolved per request, so an app can switch environments at runtime (e.g. from a QA debug menu)
/// without rebuilding the client.
public protocol EnvironmentResolver: Sendable {
    func currentEnvironment() async -> NetworkEnvironment
}
