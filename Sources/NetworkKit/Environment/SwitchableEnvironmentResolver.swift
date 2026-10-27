import Foundation

/// An environment that can be changed at runtime, e.g. from a QA build's debug menu.
/// Requests already in flight keep the environment they started with.
///
/// Remember to clear cached responses and stored tokens when switching, since they belong to
/// the previous environment.
public actor SwitchableEnvironmentResolver: EnvironmentResolver {
    private var environment: NetworkEnvironment

    public init(initial environment: NetworkEnvironment) {
        self.environment = environment
    }

    public func currentEnvironment() async -> NetworkEnvironment {
        environment
    }

    public func switchTo(_ environment: NetworkEnvironment) {
        self.environment = environment
    }
}
