import XCTest
@testable import BluprintsProtocol
final class PrintJobTests: XCTestCase {
    func testLinkPreservesBinaryBytes() throws {
        let url = URL(string: "bluprintsprint://print?jobId=abc-1&format=raw&data=AAEC-_8")!
        guard case .job(let job) = try PrintJob.link(url) else { return XCTFail("Expected job") }
        XCTAssertEqual(job.bytes, Data([0,1,2,251,255]))
    }
    func testDuplicateParametersRejected() {
        XCTAssertThrowsError(try PrintJob.link(URL(string: "bluprintsprint://print?jobId=a&jobId=b&format=raw&data=QQ")!))
    }
    func testBadLinksRejected() {
        for s in ["http://print?jobId=a&format=raw&data=QQ", "bluprintsprint://print?jobUrl=http%3A%2F%2Fexample.com", "bluprintsprint://print?jobId=a&format=raw&data=***", "bluprintsprint://print?jobId=a&format=pdf&data=QQ", "bluprintsprint://print?jobId=a&format=raw&data="] {
            XCTAssertThrowsError(try PrintJob.link(URL(string:s)!))
        }
    }
    func testRemoteURL() throws {
        let input = URL(string: "bluprintsprint://print?jobUrl=https%3A%2F%2Fexample.com%2Fjob.json")!
        guard case .remote(let url) = try PrintJob.link(input) else { return XCTFail("Expected remote URL") }
        XCTAssertEqual(url.absoluteString, "https://example.com/job.json")
    }
    func testSizeLimit() { XCTAssertThrowsError(try PrintJob(id: "a", format: "raw", bytes: Data(repeating: 0, count: PrintJob.maxBytes + 1))) }
    func testJSON() throws {
        let job = try PrintJob.json(Data(#"{"jobId":"json-1","format":"escpos","dataBase64":"G0BIZWxsbwo="}"#.utf8))
        XCTAssertEqual(job.bytes, Data([27,64,72,101,108,108,111,10]))
    }
}
