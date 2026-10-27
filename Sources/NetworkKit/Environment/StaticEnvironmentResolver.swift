import Foundation

/// Always resolves to the same environment. The usual choice for release builds.
public struct StaticEnvironmentResolver: EnvironmentResolver {
    private let environment: NetworkEnvironment

    public init(_ environment: NetworkEnvironment) {
        self.environment = environment
    }

    public func currentEnvironment() async -> NetworkEnvironment {
        environment
    }
}
