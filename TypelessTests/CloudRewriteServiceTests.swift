import XCTest
@testable import Nano_Typeless

final class CloudRewriteServiceTests: XCTestCase {

    func testRewriteOrPassthroughFallsBackOn401() async {
        let service = CloudRewriteService(
            session: makeSession(statusCode: 401, body: "{}"),
            baseEndpoint: "https://test.openai.azure.com",
            deploymentName: "test-model",
            apiKeyProvider: { "test-key" }
        )

        let input = "hello world"
        let output = await service.rewriteOrPassthrough(input)
        XCTAssertEqual(output, input)
    }

    func testRewriteOrPassthroughFallsBackOn429() async {
        let service = CloudRewriteService(
            session: makeSession(statusCode: 429, body: "{}"),
            baseEndpoint: "https://test.openai.azure.com",
            deploymentName: "test-model",
            apiKeyProvider: { "test-key" }
        )

        let input = "hello world"
        let output = await service.rewriteOrPassthrough(input)
        XCTAssertEqual(output, input)
    }

    func testRewriteOrPassthroughFallsBackOn5xx() async {
        let service = CloudRewriteService(
            session: makeSession(statusCode: 503, body: "{}"),
            baseEndpoint: "https://test.openai.azure.com",
            deploymentName: "test-model",
            apiKeyProvider: { "test-key" }
        )

        let input = "hello world"
        let output = await service.rewriteOrPassthrough(input)
        XCTAssertEqual(output, input)
    }

    func testRewriteOrPassthroughFallsBackOnNetworkError() async {
        MockURLProtocol.requestHandler = { _ in
            throw URLError(.notConnectedToInternet)
        }

        let service = CloudRewriteService(
            session: makeSessionWithMockProtocol(),
            baseEndpoint: "https://test.openai.azure.com",
            deploymentName: "test-model",
            apiKeyProvider: { "test-key" }
        )

        let input = "hello world"
        let output = await service.rewriteOrPassthrough(input)
        XCTAssertEqual(output, input)
    }

    func testRewriteOrPassthroughFallsBackOnTimeout() async {
        MockURLProtocol.requestHandler = { _ in
            throw URLError(.timedOut)
        }

        let service = CloudRewriteService(
            session: makeSessionWithMockProtocol(),
            baseEndpoint: "https://test.openai.azure.com",
            deploymentName: "test-model",
            apiKeyProvider: { "test-key" }
        )

        let input = "hello world"
        let output = await service.rewriteOrPassthrough(input)
        XCTAssertEqual(output, input)
    }

    func testRewriteOrPassthroughReturnsRewrittenTextOnSuccess() async {
        let body = """
        {
          "choices": [
            { "message": { "role": "assistant", "content": "rewritten text" } }
          ]
        }
        """

        let service = CloudRewriteService(
            session: makeSession(statusCode: 200, body: body),
            baseEndpoint: "https://test.openai.azure.com",
            deploymentName: "test-model",
            apiKeyProvider: { "test-key" }
        )

        let output = await service.rewriteOrPassthrough("hello world")
        XCTAssertEqual(output, "rewritten text")
    }

    func testRewriteOrPassthroughBypassesWhenNoApiKey() async {
        let service = CloudRewriteService(
            baseEndpoint: "https://test.openai.azure.com",
            apiKeyProvider: { nil }
        )
        let input = "hello world"
        let output = await service.rewriteOrPassthrough(input)
        XCTAssertEqual(output, input)
    }

    private func makeSession(statusCode: Int, body: String) -> URLSession {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url ?? URL(string: "https://example.com")!,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, body.data(using: .utf8) ?? Data())
        }
        return makeSessionWithMockProtocol()
    }

    private func makeSessionWithMockProtocol() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }
}

private final class MockURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
