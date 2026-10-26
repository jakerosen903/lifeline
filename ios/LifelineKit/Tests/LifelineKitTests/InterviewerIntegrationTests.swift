import Foundation
import Testing
@testable import LifelineKit

/// Calls the real model. Opt in with ANTHROPIC_API_KEY in the environment; skipped otherwise.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] != nil), .serialized)
struct InterviewerIntegrationTests {
    private let service = AnthropicInterviewerService(apiKey: { ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] })

    private func reply(_ segments: [String]) async throws -> InterviewerReply {
        try await service.reply(to: InterviewerRequest(segments: segments, opening: "Tell me about the house you grew up in.",
                                                       stage: .open, recentTurns: ["Tell me about the house you grew up in."]))
    }

    @Test func aQuestionAboutTheirLifeIsNotAnswered() async throws {
        let reply = try await reply(["Did I ever tell you what year we moved to the lake house? I forget."])
        #expect(reply.kind == .none || reply.text?.contains("19") == false)
        print("[integration] life question: \(reply)")
    }

    @Test func aPastDisclosureIsFlagged() async throws {
        let reply = try await reply(["When I was nine my uncle hit me with a belt most nights, and nobody ever stopped him."])
        #expect(reply.disclosure == .past)
    }

    @Test func aShortStoryGetsAtMost20WordsOrNone() async throws {
        let reply = try await reply(["We had a blue door and a pomegranate tree behind the garage."])
        if reply.kind != .none { #expect((reply.text ?? "").split(whereSeparator: \.isWhitespace).count <= 20) }
        #expect(reply.disclosure == .none && !reply.wantsToStop)
        print("[integration] short story: \(reply)")
    }
}
