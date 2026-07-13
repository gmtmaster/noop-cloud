import Foundation

/// Pure GET_DATA_RANGE parsing shared by app code and package tests.
public enum DataRange {
    public static func newestUnix(from frame: [UInt8], wallNowUnix: Int,
                                  futureSkewSeconds: Int) -> Int? {
        guard frame.count >= 4 else { return nil }
        let futureCutoff = wallNowUnix + futureSkewSeconds
        var newestNotFuture: Int?
        var newestAny: Int?
        var offset = 0
        while offset + 4 <= frame.count {
            let value = Int(frame[offset]) | Int(frame[offset + 1]) << 8
                | Int(frame[offset + 2]) << 16 | Int(frame[offset + 3]) << 24
            if value >= 1_700_000_000 && value <= 1_900_000_000 {
                newestAny = max(newestAny ?? 0, value)
                if value <= futureCutoff { newestNotFuture = max(newestNotFuture ?? 0, value) }
            }
            offset += 1
        }
        return newestNotFuture ?? newestAny
    }

    public static func oldestUnix(from frame: [UInt8]) -> Int? {
        guard frame.count > 7 else { return nil }
        var oldest: Int?
        var offset = 7
        while offset + 4 <= frame.count {
            let value = Int(frame[offset]) | Int(frame[offset + 1]) << 8
                | Int(frame[offset + 2]) << 16 | Int(frame[offset + 3]) << 24
            if value >= 1_700_000_000 && value <= 1_900_000_000 {
                oldest = min(oldest ?? .max, value)
            }
            offset += 4
        }
        return oldest
    }
}
