import Foundation
import Testing
@testable import MediaPipeline

@Test func rtpReorderBufferRestoresSequenceAndHandlesWraparound() {
    var buffer = RTPReorderBuffer(maximumHold: 3)
    func packet(_ sequence: UInt16) -> RTPBufferedPacket {
        RTPBufferedPacket(
            header: RTPHeader(payloadType: 120, sequence: sequence, timestamp: UInt32(sequence), ssrc: 1),
            payload: Data([UInt8(truncatingIfNeeded: sequence)])
        )
    }
    #expect(buffer.insert(packet(65_534)).map(\.header.sequence) == [65_534])
    #expect(buffer.insert(packet(0)).isEmpty)
    #expect(buffer.insert(packet(65_535)).map(\.header.sequence) == [65_535, 0])
    #expect(buffer.insert(packet(0)).isEmpty)
}

@Test func rtpReorderBufferSkipsAConfirmedGap() {
    var buffer = RTPReorderBuffer(maximumHold: 3)
    func packet(_ sequence: UInt16) -> RTPBufferedPacket {
        RTPBufferedPacket(
            header: RTPHeader(payloadType: 101, sequence: sequence, timestamp: 1, ssrc: 1),
            payload: Data([1])
        )
    }
    #expect(buffer.insert(packet(10)).map(\.header.sequence) == [10])
    #expect(buffer.insert(packet(12)).isEmpty)
    #expect(buffer.takeNewMissingSequences() == [11])
    #expect(buffer.insert(packet(13)).isEmpty)
    #expect(buffer.takeNewMissingSequences().isEmpty)
    #expect(buffer.insert(packet(14)).map(\.header.sequence) == [12, 13, 14])
    let didSkipGap = buffer.takeSkippedGap()
    let didSkipAgain = buffer.takeSkippedGap()
    #expect(didSkipGap)
    #expect(!didSkipAgain)
}

@Test func rtpReorderBufferClearsPendingNACKWhenRetransmissionArrives() {
    var buffer = RTPReorderBuffer(maximumHold: 4)
    func packet(_ sequence: UInt16) -> RTPBufferedPacket {
        RTPBufferedPacket(
            header: RTPHeader(payloadType: 101, sequence: sequence, timestamp: 1, ssrc: 1),
            payload: Data([1])
        )
    }

    #expect(buffer.insert(packet(65_535)).map(\.header.sequence) == [65_535])
    #expect(buffer.insert(packet(1)).isEmpty)
    #expect(buffer.takeNewMissingSequences() == [0])
    #expect(buffer.insert(packet(0)).map(\.header.sequence) == [0, 1])
    #expect(buffer.takeNewMissingSequences().isEmpty)
    let didSkipGap = buffer.takeSkippedGap()
    #expect(!didSkipGap)
}
