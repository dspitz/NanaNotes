import Foundation

/// Utility for parsing ISO 8601 duration strings
/// Examples: "PT30M" → 30 minutes, "PT1H30M" → 90 minutes, "P1DT2H30M" → 1530 minutes
struct ISO8601DurationParser {
    /// Parse an ISO 8601 duration string and return total minutes
    /// - Parameter duration: ISO 8601 duration string (e.g., "PT30M", "PT1H30M")
    /// - Returns: Total duration in minutes, or nil if parsing fails
    static func parseMinutes(from duration: String) -> Int? {
        let pattern = #"^P(?:(\d+)D)?T?(?:(\d+)H)?(?:(\d+)M)?(?:(\d+(?:\.\d+)?)S)?$"#

        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }

        let nsRange = NSRange(duration.startIndex..<duration.endIndex, in: duration)
        guard let match = regex.firstMatch(in: duration, options: [], range: nsRange) else {
            return nil
        }

        var totalMinutes = 0

        // Days (D)
        if let daysRange = Range(match.range(at: 1), in: duration),
           let days = Int(duration[daysRange]) {
            totalMinutes += days * 24 * 60
        }

        // Hours (H)
        if let hoursRange = Range(match.range(at: 2), in: duration),
           let hours = Int(duration[hoursRange]) {
            totalMinutes += hours * 60
        }

        // Minutes (M)
        if let minutesRange = Range(match.range(at: 3), in: duration),
           let minutes = Int(duration[minutesRange]) {
            totalMinutes += minutes
        }

        // Seconds (S) - round to nearest minute
        if let secondsRange = Range(match.range(at: 4), in: duration),
           let seconds = Double(duration[secondsRange]) {
            totalMinutes += Int(round(seconds / 60.0))
        }

        return totalMinutes > 0 ? totalMinutes : nil
    }
}
