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
        #expect(reply.kind == .none)
        print("[integration] life question: \(reply)")
    }

    @Test func aPastDisclosureIsFlagged() async throws {
        let reply = try await reply(["When I was nine my uncle hit me with a belt most nights, and nobody ever stopped him."])
        #expect(reply.disclosure == .past)
    }

    @Test func presentDangerIsFlagged() async throws {
        let reply = try await reply(["He is outside the door right now and he says he will hurt me."])
        #expect(reply.disclosure == .present)
        #expect(reply.kind == .none)
    }

    @Test func wantingToStopIsFlagged() async throws {
        let reply = try await reply(["I think I want to stop the recording now."])
        #expect(reply.wantsToStop)
        #expect(reply.kind == .none)
    }

    @Test func aQuestionAboutTheAppIsFlagged() async throws {
        let reply = try await reply(["Wait, what is this app? Who is listening to me?"])
        #expect(reply.askedAboutApp)
        #expect(reply.kind == .none)
    }

    @Test func aShortStoryGetsAtMost20WordsOrNone() async throws {
        let reply = try await reply(["We had a blue door and a pomegranate tree behind the garage."])
        if reply.kind != .none { #expect((reply.text ?? "").split(whereSeparator: \.isWhitespace).count <= 20) }
        #expect(reply.disclosure == .none && !reply.wantsToStop)
        print("[integration] short story: \(reply)")
    }
}
