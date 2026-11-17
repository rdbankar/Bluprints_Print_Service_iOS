import Foundation
import Combine

// Bounded HTTPS JSON download. No redirects, cookies or browser session assumptions.
final class JobDownloader: NSObject, URLSessionDataDelegate {
    private var session: URLSession?
    private var buffer = Data()
    private var completion: ((Result<Data, Error>) -> Void)?
    private let limit = 3 * 1024 * 1024
    func start(_ url: URL, completion: @escaping (Result<Data, Error>) -> Void) {
        self.completion = completion
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false; config.httpCookieStorage = nil
        config.timeoutIntervalForRequest = 20; config.timeoutIntervalForResource = 30
        let session = URLSession(configuration: config, delegate: self, delegateQueue: .main)
        self.session = session
        var request = URLRequest(url: url); request.setValue("application/json", forHTTPHeaderField: "Accept")
        session.dataTask(with: request).resume()
    }
    private func finish(_ result: Result<Data, Error>) {
        guard let callback = completion else { return }; completion = nil
        session?.invalidateAndCancel(); session = nil; callback(result)
    }
    func cancel() { finish(.failure(PrintJob.Failure.invalid("Download cancelled"))) }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil); finish(.failure(PrintJob.Failure.invalid("Redirects are not accepted. Supply the final HTTPS job URL.")))
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let response = response as? HTTPURLResponse, response.statusCode == 200,
              response.expectedContentLength <= Int64(limit) else {
            completionHandler(.cancel); finish(.failure(PrintJob.Failure.invalid("Job server must return HTTP 200 and at most 3 MiB of JSON."))); return
        }
        completionHandler(.allow)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard buffer.count + data.count <= limit else { finish(.failure(PrintJob.Failure.invalid("Job response exceeds 3 MiB."))); return }
        buffer.append(data)
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error { finish(.failure(error)) } else { finish(.success(buffer)) }
    }
}

final class JobInbox: ObservableObject {
    @Published var job: PrintJob?
    @Published var remoteURL: URL?
    @Published var loading = false
    @Published var message = "Open a print link from Chrome, import a file, or load a test job."
    private var downloader: JobDownloader?
    func receive(_ url: URL, busy: Bool) {
        guard !busy, !loading else { message = "New link rejected while a transfer or download is in progress. Open it again when finished."; return }
        do {
            switch try PrintJob.link(url) {
            case .job(let incoming): job = incoming; remoteURL = nil; message = "Job received. Review it, then tap Send to printer."
            case .remote(let source): remoteURL = source; job = nil; message = "Review the server address, then tap Download job."
            }
        } catch { message = error.localizedDescription }
    }
    func fetch() {
        guard let url = remoteURL, !loading else { return }; loading = true
        let loader = JobDownloader(); downloader = loader
        loader.start(url) { [weak self] result in
            guard let self = self else { return }; self.loading = false; self.downloader = nil
            do { self.job = try PrintJob.json(result.get()); self.remoteURL = nil; self.message = "Job downloaded. Review before sending." }
            catch { self.message = error.localizedDescription }
        }
    }
    func cancelDownload() { downloader?.cancel() }
    func load(_ job: PrintJob) { self.job = job; remoteURL = nil; message = "Review the job and selected printer before sending." }
    func importFile(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource(); defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
            let data = try handle.read(upToCount: PrintJob.maxBytes + 1) ?? Data()
            if url.pathExtension.lowercased() == "json" { load(try PrintJob.json(data)) }
            else { load(try PrintJob(id: "file-" + UUID().uuidString, format: "raw", bytes: data)) }
        } catch { message = error.localizedDescription }
    }
}
