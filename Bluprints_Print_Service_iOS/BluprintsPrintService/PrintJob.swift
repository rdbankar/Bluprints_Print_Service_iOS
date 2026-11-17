import Foundation

struct PrintJob: Identifiable {
    let id: String
    let format: String
    let bytes: Data
    static let maxBytes = 2 * 1024 * 1024
    static let maxLinkBytes = 32 * 1024

    enum Failure: LocalizedError {
        case invalid(String)
        var errorDescription: String? { if case let .invalid(s) = self { return s }; return nil }
    }
    init(id: String, format: String, bytes: Data) throws {
        guard !id.isEmpty, id.count <= 100,
              id.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_.")).contains($0) }) else {
            throw Failure.invalid("Job ID must contain 1–100 letters, digits, hyphens, underscores or dots.")
        }
        guard ["escpos", "tspl", "raw"].contains(format) else { throw Failure.invalid("Format must be escpos, tspl or raw.") }
        guard !bytes.isEmpty, bytes.count <= Self.maxBytes else { throw Failure.invalid("Job must contain 1 byte to 2 MiB.") }
        self.id = id; self.format = format; self.bytes = bytes
    }
    static func decode(_ value: String) throws -> Data {
        var s = value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        s += String(repeating: "=", count: (4 - s.count % 4) % 4)
        guard let d = Data(base64Encoded: s) else { throw Failure.invalid("Invalid Base64 payload.") }
        return d
    }
    static func json(_ data: Data) throws -> PrintJob {
        struct Envelope: Decodable { let jobId: String; let format: String; let dataBase64: String }
        let e = try JSONDecoder().decode(Envelope.self, from: data)
        return try PrintJob(id: e.jobId, format: e.format.lowercased(), bytes: decode(e.dataBase64))
    }
    enum Incoming { case job(PrintJob), remote(URL) }
    static func link(_ url: URL) throws -> Incoming {
        guard url.absoluteString.utf8.count <= maxLinkBytes,
              url.scheme?.lowercased() == "bluprintsprint", url.host?.lowercased() == "print",
              url.path.isEmpty || url.path == "/",
              url.user == nil, url.password == nil, url.port == nil, url.fragment == nil,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw Failure.invalid("Invalid print link (maximum 32 KiB).")
        }
        var params: [String: String] = [:]
        for item in components.queryItems ?? [] {
            guard ["jobId", "format", "data", "jobUrl"].contains(item.name), params[item.name] == nil, let value = item.value else {
                throw Failure.invalid("Unknown, repeated or empty link parameter.")
            }
            params[item.name] = value
        }
        if let source = params["jobUrl"] {
            guard params.count == 1, let remote = URL(string: source), remote.scheme?.lowercased() == "https",
                  let host = remote.host, !host.isEmpty, remote.user == nil, remote.password == nil,
                  remote.fragment == nil else { throw Failure.invalid("jobUrl must be an HTTPS URL without embedded credentials or fragment.") }
            return .remote(remote)
        }
        guard let id = params["jobId"], let format = params["format"], let data = params["data"], params.count == 3 else {
            throw Failure.invalid("Provide jobId, format and data; or provide jobUrl alone.")
        }
        return .job(try PrintJob(id: id, format: format.lowercased(), bytes: decode(data)))
    }
    static func receipt() -> PrintJob {
        try! PrintJob(id: "test-" + UUID().uuidString, format: "escpos", bytes: Data(("\u{1b}@BLUPRINTS PRINT SERVICE\n------------------------\niPhone BLE print test\n0123456789 ABCDEFGHIJKLMN\n\n\n").utf8))
    }
    static func label() -> PrintJob {
        let text = "SIZE 50 mm,30 mm\r\nGAP 2 mm,0 mm\r\nDIRECTION 1\r\nCLS\r\nTEXT 20,20,\"3\",0,1,1,\"BLUPRINTS BLE\"\r\nTEXT 20,60,\"2\",0,1,1,\"iPhone print test\"\r\nPRINT 1,1\r\n"
        return try! PrintJob(id: "label-" + UUID().uuidString, format: "tspl", bytes: Data(text.utf8))
    }
}
