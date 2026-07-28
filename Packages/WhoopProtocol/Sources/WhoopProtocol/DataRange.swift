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

    /// #689/#815: the ring-buffer page backlog ("pages behind") the strap reports in a GET_DATA_RANGE
    /// response — DIAGNOSTIC ONLY (feeds a future sync-progress UI, never gates sync or backfill itself).
    /// Confirmed against real captures on both WHOOP 4.0 (#791) and 5.0/MG (#815): the write/read pointers
    /// and ring capacity below all landed exactly where this predicts, across four independent frames.
    ///
    /// The app reads three u32s from the command-response INNER payload (whose byte 0 is a subtype), at
    /// `V(i) = word @ (i*4 + 3)`: write pointer `W = V(2)`, read pointer `U = V(3)`, ring capacity `T = V(5)`.
    /// The inner payload starts at `cmdOff + 1`, so those words sit at frame offsets `cmdOff + 12/16/24`
    /// here. Read u32 LITTLE-endian to match the frame's other words. Backlog with wraparound (unverified —
    /// no real capture has crossed it yet, but harmless to ship since this only ever feeds a diagnostic):
    /// `W < U ? W + (T - U) : W - U`. `T` has been `131072` in every real capture so far (both families) but
    /// is still read from the frame each time rather than hardcoded, in case a firmware revision differs.
    ///
    /// Returns nil for a too-short frame or implausible values — a capacity that is 0 or above a sane
    /// ceiling (a misaligned read hitting a timestamp / `0xFFFFFFFF`), a pointer at/beyond capacity, or a
    /// backlog past capacity — so a garbage frame can never log a nonsense number.
    public static func pagesBehind(from frame: [UInt8], cmdOff: Int) -> Int? {
        guard cmdOff >= 0 else { return nil }
        let payloadOffset = cmdOff + 1
        let wOff = payloadOffset + 11, uOff = payloadOffset + 15, tOff = payloadOffset + 23
        guard tOff + 4 <= frame.count else { return nil }
        func u32(_ o: Int) -> Int {
            Int(frame[o]) | Int(frame[o + 1]) << 8 | Int(frame[o + 2]) << 16 | Int(frame[o + 3]) << 24
        }
        let w = u32(wOff), u = u32(uOff), t = u32(tOff)
        guard t > 0, t <= 0x00FF_FFFF, w < t, u < t else { return nil }
        let behind = w < u ? w + (t - u) : w - u
        guard behind >= 0, behind <= t else { return nil }
        return behind
    }
}
