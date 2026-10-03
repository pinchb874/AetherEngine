import Testing
import Foundation
@testable import AetherEngine

/// A live source is produced in real time, so a read that insists on filling its whole request waits
/// for bytes that do not exist yet. On a sparse stream (a still slate at ~130 kbit/s) that held the
/// probe ~15 s on data that had arrived in the first 6. A live read now hands over what it has once it
/// has waited `liveShortReadAfterMs` past its first byte; a normal-rate source still fills the request.
@Suite("AVIOReader live short read")
struct LiveShortReadTests {

    @Test("a sparse live source hands over a partial read instead of waiting to fill it",
          .timeLimit(.minutes(1)))
    func sparseLiveReadIsShort() async throws {
        // 4 KB every 250 ms: 16 KB/s, so a 256 KB request would take ~16 s to fill.
        let server = try #require(ThrottledOriginServer(totalSize: 64 * 1024 * 1024,
                                                        chunkBytes: 4 * 1024, throttleUs: 250_000))
        defer { server.stop() }
        let reader = AVIOReader(url: URL(string: "http://127.0.0.1:\(server.port)/live.ts")!,
                                isLive: true, connStallTimeout: 600)
        defer { reader.markClosed(); reader.close() }
        try reader.open()

        let size = 256 * 1024
        let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: size)
        defer { buf.deallocate() }
        let started = Date()
        let n = reader.read(into: buf, size: Int32(size))
        let took = Date().timeIntervalSince(started)
        #expect(n > 0, "the read returned \(n)")
        #expect(Int(n) < size, "a sparse source filled the whole request")
        #expect(took < 4, "the read took \(took) s; a partial read is due ~0.5 s after the first byte")
    }

    @Test("a normal-rate live source still fills the request", .timeLimit(.minutes(1)))
    func fastLiveReadIsFull() async throws {
        let server = try #require(ThrottledOriginServer(totalSize: 64 * 1024 * 1024))
        defer { server.stop() }
        let reader = AVIOReader(url: URL(string: "http://127.0.0.1:\(server.port)/live.ts")!,
                                isLive: true, connStallTimeout: 600)
        defer { reader.markClosed(); reader.close() }
        try reader.open()

        let size = 256 * 1024
        let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: size)
        defer { buf.deallocate() }
        let n = reader.read(into: buf, size: Int32(size))
        #expect(Int(n) == size, "a fast source returned \(n) of \(size) bytes")
    }
}
