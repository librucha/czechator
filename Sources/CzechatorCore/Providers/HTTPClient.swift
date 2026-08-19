import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

public enum HTTPError: Error, Equatable {
    case status(code: Int, body: String)
    case transport(String)
}

public protocol HTTPClient: Sendable {
    func post(
        url: URL,
        headers: [String: String],
        body: Data,
        timeout: TimeInterval
    ) async throws -> Data
}

public struct URLSessionHTTPClient: HTTPClient {

    private let session: URLSession

    public init(session: URLSession = .shared) { self.session = session }

    public func post(
        url: URL,
        headers: [String: String],
        body: Data,
        timeout: TimeInterval
    ) async throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw HTTPError.transport(error.localizedDescription)
        }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw HTTPError.status(
                code: http.statusCode, body: String(decoding: data, as: UTF8.self))
        }
        return data
    }
}
