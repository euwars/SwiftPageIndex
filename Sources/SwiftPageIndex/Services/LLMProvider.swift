import AnyLanguageModel
import Foundation

// MARK: - @Generable response types

@Generable
public struct TocItem: Sendable {
  @Guide(description: "Hierarchy index, e.g. '1', '1.1', '2'")
  public var structure: String
  @Guide(description: "Exact section title from the text")
  public var title: String
  @Guide(description: "Page number where section starts")
  public var physicalIndex: Int
}

@Generable
public struct TocResponse: Sendable {
  @Guide(description: "Array of table of contents items")
  public var items: [TocItem]
}

@Generable
public enum ConfidenceLevel: Sendable {
  case low
  case medium
  case high
}

@Generable
public struct LLMSearchResponse: Sendable {
  @Guide(description: "IDs of selected relevant nodes")
  public var selectedNodes: [String]
  @Guide(description: "Brief explanation of selection")
  public var reasoning: String
  @Guide(description: "Confidence level")
  public var confidence: ConfidenceLevel
  @Guide(description: "Whether the answer was found in selected nodes")
  public var foundAnswer: Bool
}

@Generable
public struct PageTextExtraction: Sendable {
  @Guide(description: "Full extracted text from the page")
  public var text: String
  @Guide(description: "Detected section headers with their levels")
  public var sections: [DetectedSection]
}

@Generable
public struct DetectedSection: Sendable {
  @Guide(description: "Header level 1-6")
  public var level: Int
  @Guide(description: "Section title text")
  public var title: String
}

// MARK: - LLM Provider wrapper

public struct PageIndexLLM: Sendable {
  private let makeSession: @Sendable () -> LanguageModelSession

  public init(apiKey: String, model: String = "gpt-4o-mini") {
    let lm = OpenAILanguageModel(apiKey: apiKey, model: model)
    makeSession = { LanguageModelSession(model: lm) }
  }

  public init(model: some LanguageModel) {
    makeSession = { LanguageModelSession(model: model) }
  }

  /// Structured response using @Generable schema
  public func generate<T: Generable & Sendable>(
    _ prompt: String,
    as type: T.Type,
    temperature: Double = 0.1,
    maxTokens: Int = 2000,
  ) async throws -> T {
    let session = makeSession()
    let options = GenerationOptions(
      temperature: temperature,
      maximumResponseTokens: maxTokens,
    )
    let response = try await session.respond(
      to: prompt,
      generating: type,
      options: options,
    )
    return response.content
  }

  /// Plain text response
  public func chat(
    _ prompt: String,
    temperature: Double = 0.1,
    maxTokens: Int = 2000,
  ) async throws -> String {
    let session = makeSession()
    let options = GenerationOptions(
      temperature: temperature,
      maximumResponseTokens: maxTokens,
    )
    let response = try await session.respond(
      to: prompt,
      options: options,
    )
    return response.content
  }
}
