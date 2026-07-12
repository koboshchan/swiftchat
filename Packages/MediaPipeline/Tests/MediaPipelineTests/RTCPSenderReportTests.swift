import Foundation
import Testing
@testable import MediaPipeline

@Test func rtcpSenderReportUsesRFC3550Layout() throws {
    var tracker = RTCPSenderTracker()
    tracker.record(packets: 3, octets: 1_500)
    let date = Date(timeIntervalSince1970: 1_700_000_000.5)
    let pendingReport = tracker.reportIfDue(ssrc: 42, rtpTimestamp: 90_000, now: date)
    let report = try #require(pendingReport)
    #expect(report.header == Data([0x80, 200, 0, 6, 0, 0, 0, 42]))
    #expect(report.payload.count == 20)
    #expect(report.payload.readUInt32BigEndian(at: 8) == 90_000)
    #expect(report.payload.readUInt32BigEndian(at: 12) == 3)
    #expect(report.payload.readUInt32BigEndian(at: 16) == 1_500)
    #expect(tracker.reportIfDue(ssrc: 42, rtpTimestamp: 90_001, now: date.addingTimeInterval(0.5)) == nil)
}
