import Foundation

/// A per-task `URLSessionTaskDelegate` that forwards the task's collected metrics.
public final class NetworkTaskMetricsDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    private let handler: @Sendable (NetworkMetrics) -> Void

    public init(handler: @escaping @Sendable (NetworkMetrics) -> Void) {
        self.handler = handler
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        handler(NetworkMetrics(metrics))
    }
}
