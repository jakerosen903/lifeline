import Foundation
import Synchronization
@testable import LifelineKit

/// Scripted HTTP responses. Each `send` consumes the next entry; running out is a test bug.
final class FakeHTTPTransport: HTTPTransport, Sendable {
    enum Scripted {
        case response(status: Int, body: String, headers: [String: String] = [:])
        case error(any Error)
    }

    private let state = Mutex<(script: [Scripted], requests: [URLRequest])>(([], []))

    init(_ script: [Scripted]) { state.withLock { $0.script = script } }

    var requests: [URLRequest] { state.withLock { $0.requests } }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let next: Scripted = state.withLock { s in
            s.requests.append(request)
            return s.script.isEmpty ? .error(URLError(.badServerResponse)) : s.script.removeFirst()
        }
        switch next {
        case .error(let error): throw error
        case .response(let status, let body, let headers):
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!
            return (Data(body.utf8), response)
        }
    }

    func body(of index: Int) throws -> [String: Any] {
        let data = try #require(requests[index].httpBody)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
import Testing

/// Sleep recorder for retry tests: no real waiting.
final class SleepRecorder: Sendable {
    private let slept = Mutex<[Duration]>([])
    var durations: [Duration] { slept.withLock { $0 } }
    func sleep(_ d: Duration) async { slept.withLock { $0.append(d) } }
}

enum APIBodies {
    static let gardenOutput = """
    {"memories":[{"ref":"m1","title":"The pomegranate tree","quote":"the garden had a pomegranate tree","segment_span":{"start_word":0,"end_word":5},"people_refs":[],"place_text":null,"anchors":[],"same_as_memory_id":null,"collection_hint":null,"chapter_hint":null,"confidence":0.9}],"mentions":[],"flags":{"serious_disclosure":false,"wants_to_stop":false,"wants_to_change_subject":false}}
    """
    static func success(text: String = gardenOutput, model: String = "claude-opus-5-5") -> String {
        let escaped = text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        return """
        {"id":"msg_1","type":"message","role":"assistant","model":"\(model)","stop_reason":"end_turn","stop_details":null,
         "content":[{"type":"text","text":"\(escaped)"}],
         "usage":{"input_tokens":1200,"output_tokens":180,"cache_read_input_tokens":900,"cache_creation_input_tokens":0}}
        """
    }
    static let refusal = """
    {"id":"msg_2","type":"message","role":"assistant","model":"claude-opus-5-5","stop_reason":"refusal",
     "stop_details":{"type":"refusal","category":"cyber","explanation":null},"content":[],
     "usage":{"input_tokens":10,"output_tokens":0}}
    """
    static let truncated = """
    {"id":"msg_3","type":"message","role":"assistant","model":"claude-opus-5-5","stop_reason":"max_tokens","stop_details":null,
     "content":[{"type":"text","text":"{\\"memories\\":["}],"usage":{"input_tokens":10,"output_tokens":4096}}
    """
    static let apiError = """
    {"type":"error","error":{"type":"rate_limit_error","message":"slow down"}}
    """
}
