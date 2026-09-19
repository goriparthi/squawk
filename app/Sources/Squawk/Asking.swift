import Foundation
import SquawkCore

/// Answering a question the pet was asked. The order matters more than any
/// part of it: anything with a right answer available is worked out, and only
/// what is genuinely open ended reaches a model.
///
/// A language model states today's date with complete confidence and is wrong,
/// because it cannot know it. The clock is not a thing to be generated.
@MainActor
final class Asking {
    private let conversation = Conversation()

    func forget() { conversation.clear() }

    /// Always answers with something sayable, even when everything failed.
    func answer(_ question: String, model: String?, place: String?,
                completion: @escaping @Sendable (String) -> Void) {
        if let exact = Answers.exact(for: question) { return completion(exact) }
        if Answers.isAboutWeather(question) {
            Weather.spoken(place: place) { spoken in
                completion(spoken ?? "I could not reach the weather just now.")
            }
            return
        }
        guard let model else {
            return completion("I would need a small model running here to answer that. "
                + "Try ollama pull \(Ollama.suggested).")
        }
        conversation.ask(question, model: model) { [weak self] answer in
            Task { @MainActor in
                guard let answer else { return completion("I could not work that one out.") }
                self?.conversation.remember(question: question, answer: answer)
                completion(answer)
            }
        }
    }
}
