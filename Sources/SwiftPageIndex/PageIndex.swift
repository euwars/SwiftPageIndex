import AnyLanguageModel
import Foundation

// MARK: - Configuration

public struct PageIndexConfig: Sendable {
  public var openaiApiKey: String?
  public var openaiModel: String
  public var dataDir: String
  public var maxTokens: Int

  public init(
    openaiApiKey: String? = nil,
    openaiModel: String = "gpt-4o-mini",
    dataDir: String = "./data",
    maxTokens: Int = 4000,
    dotEnvPath: String? = ".env",
  ) {
    if let dotEnvPath { DotEnv.load(path: dotEnvPath) }
    self.openaiApiKey = openaiApiKey ?? ProcessInfo.processInfo.environment["OPENAI_API_KEY"]
    self.openaiModel = openaiModel
    self.dataDir = dataDir
    self.maxTokens = maxTokens
  }
}

public struct IndexOptions: Sendable {
  public var name: String?
  public var generateSummaries: Bool
  public var includeContent: Bool
  public var useLLMTreeBuilder: Bool

  public init(
    name: String? = nil,
    generateSummaries: Bool = true,
    includeContent: Bool = false,
    useLLMTreeBuilder: Bool = false,
  ) {
    self.name = name
    self.generateSummaries = generateSummaries
    self.includeContent = includeContent
    self.useLLMTreeBuilder = useLLMTreeBuilder
  }
}

public struct DocumentListItem: Sendable {
  public let id: String
  public let name: String
  public let metadata: DocumentMetadata?
  public let createdAt: Date?
  public let updatedAt: Date?
}

public struct QueryLogResult: Sendable {
  public let results: [SearchResult]
  public let iterations: [IterationLog]
}

// MARK: - PageIndex facade

public final class PageIndex: Sendable {
  private let config: PageIndexConfig
  private let treeBuilder: TreeBuilder
  private let llmTreeBuilder: LLMTreeBuilder?
  private let searcher: LLMTreeSearcher?
  private let indexManager: IndexManager
  private let llm: PageIndexLLM?

  public init(config: PageIndexConfig) {
    self.config = config

    treeBuilder = TreeBuilder(options: TreeBuilderOptions(
      generateSummaries: true,
      maxSummaryLength: 500,
    ))

    if let apiKey = config.openaiApiKey {
      let llm = PageIndexLLM(apiKey: apiKey, model: config.openaiModel)
      self.llm = llm
      llmTreeBuilder = LLMTreeBuilder(llm: llm)
      searcher = LLMTreeSearcher(llm: llm)
    } else {
      llm = nil
      llmTreeBuilder = nil
      searcher = nil
    }

    indexManager = IndexManager(dataDir: config.dataDir)
  }

  // MARK: - Indexing

  public func indexFromURL(_ url: URL, options: IndexOptions = IndexOptions()) async throws -> IndexedDocument {
    let (data, response) = try await URLSession.shared.data(from: url)
    let contentType = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type") ?? ""
    let fileName = url.lastPathComponent
    let name = options.name ?? URL(fileURLWithPath: fileName).deletingPathExtension().lastPathComponent

    return try await indexContent(
      data,
      name: name,
      contentType: contentType,
      sourceURL: url.absoluteString,
      options: options,
    )
  }

  public func indexFromFile(_ path: String, options: IndexOptions = IndexOptions()) async throws -> IndexedDocument {
    let url = URL(fileURLWithPath: path)
    let data = try Data(contentsOf: url)
    let name = options.name ?? URL(fileURLWithPath: url.lastPathComponent).deletingPathExtension().lastPathComponent
    let ext = url.pathExtension.lowercased()

    var contentType = "text/plain"
    if ext == "pdf" { contentType = "application/pdf" }
    else if ext == "html" || ext == "htm" { contentType = "text/html" }
    else if ext == "md" { contentType = "text/markdown" }

    return try await indexContent(data, name: name, contentType: contentType, sourceURL: path, options: options)
  }

  public func indexContent(
    _ content: Data,
    name: String,
    contentType: String = "text/plain",
    sourceURL: String? = nil,
    options: IndexOptions = IndexOptions(),
  ) async throws -> IndexedDocument {
    let parser = ParserFactory.getParser(content: content, mimeType: contentType, llm: llm)
    let parsed = try await parser.parse(content: content, sourceURL: sourceURL)

    let tree: [TreeNode] = if options.useLLMTreeBuilder, let llmBuilder = llmTreeBuilder {
      try await llmBuilder.buildTree(document: parsed)
    } else {
      treeBuilder.buildTree(document: parsed)
    }

    return try await indexManager.save(name: options.name ?? name, tree: tree, metadata: parsed.metadata)
  }

  // MARK: - Querying

  public func query(
    _ query: String,
    documentIDs: [String]? = nil,
    options: SearchOptions = SearchOptions(),
  ) async throws -> [SearchResult] {
    guard let searcher else {
      throw PageIndexError.noAPIKey
    }

    var allResults: [SearchResult] = []
    var documents: [IndexedDocument] = []

    if let ids = documentIDs, !ids.isEmpty {
      for id in ids {
        if let doc = try await indexManager.get(id) {
          documents.append(doc)
        }
      }
    } else {
      let list = try await indexManager.list()
      for item in list {
        if let doc = try await indexManager.get(item.id) {
          documents.append(doc)
        }
      }
    }

    for doc in documents {
      let results = try await searcher.search(query: query, tree: doc.structure, options: options)
      for var result in results {
        result.path = [doc.docName] + result.path
        allResults.append(result)
      }
    }

    return Array(allResults.sorted { $0.score > $1.score }.prefix(options.topK))
  }

  public func queryWithLog(
    _ query: String,
    documentID: String,
    options: SearchOptions = SearchOptions(),
  ) async throws -> QueryLogResult {
    guard let searcher else {
      throw PageIndexError.noAPIKey
    }

    guard let doc = try await indexManager.get(documentID) else {
      return QueryLogResult(results: [], iterations: [])
    }

    let result = try await searcher.searchWithLog(query: query, tree: doc.structure, options: options)
    return QueryLogResult(results: result.results, iterations: result.iterations)
  }

  // MARK: - Document management

  public func listDocuments() async throws -> [DocumentListItem] {
    try await indexManager.list().map {
      DocumentListItem(
        id: $0.id,
        name: $0.name,
        metadata: $0.metadata,
        createdAt: $0.createdAt,
        updatedAt: $0.updatedAt,
      )
    }
  }

  public func getDocument(_ id: String) async throws -> IndexedDocument? {
    try await indexManager.get(id)
  }

  public func deleteDocument(_ id: String) async throws -> Bool {
    try await indexManager.delete(id)
  }

  public func getDocumentTree(_ id: String) async throws -> [TreeNode]? {
    try await indexManager.getTree(id)
  }

  public func getTreeStats(_ tree: [TreeNode]) -> (totalNodes: Int, maxDepth: Int, avgChildrenPerNode: Double) {
    treeBuilder.getTreeStats(tree)
  }

  public func printTree(_ tree: [TreeNode]) -> String {
    treeBuilder.printTree(tree)
  }

  public func getStats() async throws -> (totalDocuments: Int, totalSize: Int, documentTypes: [String: Int]) {
    try await indexManager.getStats()
  }
}

// MARK: - Errors

public enum PageIndexError: Error, LocalizedError {
  case noAPIKey
  case parsingFailed(String)
  case indexNotFound(String)

  public var errorDescription: String? {
    switch self {
    case .noAPIKey: "No OpenAI API key provided. Set openaiApiKey in config or OPENAI_API_KEY environment variable."
    case let .parsingFailed(msg): "Parsing failed: \(msg)"
    case let .indexNotFound(id): "Index not found: \(id)"
    }
  }
}
