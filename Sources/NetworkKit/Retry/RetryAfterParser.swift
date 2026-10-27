import Foundation

/// Parses a `Retry-After` header (RFC 9110 §10.2.3): either delay-seconds or an HTTP-date.
enum RetryAfterParser {
    static func delay(from value: String, now: Date) -> TimeInterval? {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        if let seconds = Int(trimmed) {
            return seconds >= 0 ? TimeInterval(seconds) : nil
        }
        guard let date = httpDate(from: trimmed) else { return nil }
        return max(0, date.timeIntervalSince(now))
    }

    /// IMF-fixdate, e.g. `Wed, 21 Oct 2015 07:28:00 GMT`.
    /// A formatter is created per call: `DateFormatter` isn't `Sendable` and this path is rare.
    private static func httpDate(from value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter.date(from: value)
    }
}
