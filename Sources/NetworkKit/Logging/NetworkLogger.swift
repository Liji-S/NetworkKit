import Foundation

/// Receives log events. `OSLogNetworkLogger` is the default; conform your own type to forward
/// events to a crash reporter or analytics backend.
///
/// The client only calls `log` when the environment's `logLevel` is not `.off`. Use `level`
/// to decide how much detail to emit.
public protocol NetworkLogger: Sendable {
    func log(_ event: NetworkLogEvent, level: NetworkLogLevel)
}
