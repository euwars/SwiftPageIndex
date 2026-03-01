import AnyLanguageModel
import Foundation

public struct LLMTreeSearcher: Sendable {
  private let llm: PageIndexLLM
  private let treeBuilder: TreeBuilder
  private let maxIterations: Int

  public init(llm: PageIndexLLM, maxIterations: Int = 5) {
    self.llm = llm
    treeBuilder = TreeBuilder()
    self.maxIterations = maxIterations
  }

  public func search(
    query: String,
    tree: [TreeNode],
    options: SearchOptions = SearchOptions(),
  ) async throws -> [SearchResult] {
    let topK = options.topK
    let maxIter = options.maxIterations > 0 ? options.maxIterations : maxIterations

    var results: [SearchResult] = []
    var visited = Set<String>()
    var reasoningLog: [String] = []
    var currentNodes = tree
    var iteration = 0

    while iteration < maxIter, !currentNodes.isEmpty {
      iteration += 1

      let available = currentNodes.filter { !visited.contains($0.nodeId) }
      guard !available.isEmpty else { break }

      let response = try await evaluateNodes(query: query, nodes: available, iteration: iteration)

      if options.includeReasoning {
        reasoningLog.append("Iteration \(iteration): \(response.reasoning)")
      }

      for nodeId in response.selectedNodes {
        visited.insert(nodeId)
      }

      if response.foundAnswer || response.confidence == .high {
        for nodeId in response.selectedNodes {
          if let node = treeBuilder.findNodeById(tree, nodeId: nodeId) {
            let path = treeBuilder.getNodePath(tree, nodeId: nodeId) ?? []
            results.append(SearchResult(
              nodeId: node.nodeId,
              title: node.title,
              content: node.content ?? node.summary,
              summary: node.summary,
              score: confidenceToScore(response.confidence),
              path: path,
              reasoning: options.includeReasoning ? reasoningLog.joined(separator: "\n") : nil,
            ))
          }
        }
        if response.foundAnswer { break }
      }

      var nextNodes: [TreeNode] = []
      for nodeId in response.selectedNodes {
        if let node = treeBuilder.findNodeById(tree, nodeId: nodeId), !node.nodes.isEmpty {
          nextNodes.append(contentsOf: node.nodes)
        }
      }
      currentNodes = nextNodes

      if response.confidence == .low, nextNodes.isEmpty {
        let allNodes = treeBuilder.flattenTree(tree)
        currentNodes = Array(allNodes.filter { !visited.contains($0.nodeId) }.prefix(10))
      }
    }

    return Array(results.sorted { $0.score > $1.score }.prefix(topK))
  }

  public func searchWithLog(
    query: String,
    tree: [TreeNode],
    options: SearchOptions = SearchOptions(),
  ) async throws -> (results: [SearchResult], iterations: [IterationLog]) {
    let maxIter = options.maxIterations > 0 ? options.maxIterations : maxIterations
    var iterations: [IterationLog] = []
    var results: [SearchResult] = []
    var visited = Set<String>()
    var currentNodes = tree
    var iteration = 0

    while iteration < maxIter, !currentNodes.isEmpty {
      iteration += 1
      let available = currentNodes.filter { !visited.contains($0.nodeId) }
      guard !available.isEmpty else { break }

      let response = try await evaluateNodes(query: query, nodes: available, iteration: iteration)

      iterations.append(IterationLog(
        iteration: iteration,
        nodesEvaluated: available.map { "\($0.nodeId): \($0.title)" },
        selectedNodes: response.selectedNodes,
        reasoning: response.reasoning,
        confidence: response.confidence,
        foundAnswer: response.foundAnswer,
      ))

      for nodeId in response.selectedNodes {
        visited.insert(nodeId)
        if let node = treeBuilder.findNodeById(tree, nodeId: nodeId) {
          let path = treeBuilder.getNodePath(tree, nodeId: nodeId) ?? []
          results.append(SearchResult(
            nodeId: node.nodeId,
            title: node.title,
            content: node.content ?? node.summary,
            summary: node.summary,
            score: confidenceToScore(response.confidence),
            path: path,
          ))
        }
      }

      if response.foundAnswer { break }

      var nextNodes: [TreeNode] = []
      for nodeId in response.selectedNodes {
        if let node = treeBuilder.findNodeById(tree, nodeId: nodeId), !node.nodes.isEmpty {
          nextNodes.append(contentsOf: node.nodes)
        }
      }
      currentNodes = nextNodes
    }

    return (results, iterations)
  }

  // MARK: - Node evaluation

  private func evaluateNodes(query: String, nodes: [TreeNode], iteration: Int) async throws -> LLMSearchResponse {
    let nodesDesc = nodes.map { node -> [String: Any] in
      [
        "id": node.nodeId,
        "title": node.title,
        "summary": String(node.summary.prefix(300)),
        "hasChildren": !node.nodes.isEmpty,
      ]
    }

    // Serialize to JSON string manually
    let nodesJSON: String = if let data = try? JSONSerialization.data(
      withJSONObject: nodesDesc,
      options: [.prettyPrinted, .sortedKeys],
    ),
      let str = String(data: data, encoding: .utf8)
    {
      str
    } else {
      nodes.map { "[\($0.nodeId)] \($0.title): \(String($0.summary.prefix(300)))" }.joined(separator: "\n")
    }

    let prompt = """
    You are a document analysis assistant. Your task is to identify which sections of a document are most relevant to answer a user's question.

    QUESTION: "\(query)"

    AVAILABLE SECTIONS (Iteration \(iteration)):
    \(nodesJSON)

    INSTRUCTIONS:
    1. Analyze each section's title and summary
    2. Select the sections most likely to contain the answer
    3. If a section has children and the answer might be deeper, select it for drill-down
    4. Rate your confidence: LOW, MEDIUM, or HIGH
    5. Set foundAnswer to true only if you're confident the selected section(s) directly answer the question
    """

    do {
      return try await llm.generate(prompt, as: LLMSearchResponse.self, temperature: 0.1)
    } catch {
      // Fallback
      return LLMSearchResponse(
        selectedNodes: Array(nodes.prefix(2).map(\.nodeId)),
        reasoning: "Fallback selection due to LLM error",
        confidence: .low,
        foundAnswer: false,
      )
    }
  }

  private func confidenceToScore(_ confidence: ConfidenceLevel) -> Double {
    switch confidence {
    case .high: 1.0
    case .medium: 0.7
    case .low: 0.4
    }
  }
}

public struct IterationLog: Sendable {
  public let iteration: Int
  public let nodesEvaluated: [String]
  public let selectedNodes: [String]
  public let reasoning: String
  public let confidence: ConfidenceLevel
  public let foundAnswer: Bool
}
