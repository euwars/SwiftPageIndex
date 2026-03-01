import Foundation

public actor IndexManager {
  private let dataDir: String
  private let indexesDir: String
  private var cache: [String: IndexedDocument] = [:]

  public init(dataDir: String = "./data") {
    self.dataDir = dataDir
    indexesDir = URL(fileURLWithPath: dataDir).appendingPathComponent("indexes").path
  }

  private func ensureDirectories() throws {
    let fm = FileManager.default
    if !fm.fileExists(atPath: dataDir) {
      try fm.createDirectory(atPath: dataDir, withIntermediateDirectories: true)
    }
    if !fm.fileExists(atPath: indexesDir) {
      try fm.createDirectory(atPath: indexesDir, withIntermediateDirectories: true)
    }
  }

  public func save(name: String, tree: [TreeNode], metadata: DocumentMetadata) throws -> IndexedDocument {
    try ensureDirectories()
    let id = generateId(name)
    let now = Date()

    let document = IndexedDocument(
      docName: name,
      structure: tree,
      metadata: metadata,
      id: id,
      createdAt: now,
      updatedAt: now,
    )

    let filePath = getDocumentPath(id)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(document)
    try data.write(to: URL(fileURLWithPath: filePath))

    cache[id] = document
    return document
  }

  public func get(_ id: String) throws -> IndexedDocument? {
    if let cached = cache[id] {
      return cached
    }

    let filePath = getDocumentPath(id)
    guard FileManager.default.fileExists(atPath: filePath) else { return nil }

    let data = try Data(contentsOf: URL(fileURLWithPath: filePath))
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let document = try decoder.decode(IndexedDocument.self, from: data)
    cache[id] = document
    return document
  }

  public func getByName(_ name: String) throws -> IndexedDocument? {
    try get(generateId(name))
  }

  public func list() throws -> [(
    id: String,
    name: String,
    metadata: DocumentMetadata?,
    createdAt: Date?,
    updatedAt: Date?,
  )] {
    try ensureDirectories()
    let fm = FileManager.default
    let files = try fm.contentsOfDirectory(atPath: indexesDir)
    var documents: [(id: String, name: String, metadata: DocumentMetadata?, createdAt: Date?, updatedAt: Date?)] = []

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    for file in files where file.hasSuffix(".json") {
      let filePath = joinPath(indexesDir, file)
      if let data = try? Data(contentsOf: URL(fileURLWithPath: filePath)),
         let doc = try? decoder.decode(IndexedDocument.self, from: data)
      {
        documents.append((
          id: doc.id ?? generateId(doc.docName),
          name: doc.docName,
          metadata: doc.metadata,
          createdAt: doc.createdAt,
          updatedAt: doc.updatedAt,
        ))
      }
    }
    return documents
  }

  public func delete(_ id: String) throws -> Bool {
    let filePath = getDocumentPath(id)
    guard FileManager.default.fileExists(atPath: filePath) else { return false }
    try FileManager.default.removeItem(atPath: filePath)
    cache.removeValue(forKey: id)
    return true
  }

  public func update(
    _ id: String,
    docName: String? = nil,
    structure: [TreeNode]? = nil,
    metadata: DocumentMetadata? = nil,
  ) throws -> IndexedDocument? {
    guard var existing = try get(id) else { return nil }

    if let docName { existing.docName = docName }
    if let structure { existing.structure = structure }
    if let metadata { existing.metadata = metadata }
    existing.updatedAt = Date()

    let filePath = getDocumentPath(id)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(existing)
    try data.write(to: URL(fileURLWithPath: filePath))

    cache[id] = existing
    return existing
  }

  public func getTree(_ id: String) throws -> [TreeNode]? {
    try get(id)?.structure
  }

  public func getStats() throws -> (totalDocuments: Int, totalSize: Int, documentTypes: [String: Int]) {
    try ensureDirectories()
    let fm = FileManager.default
    let files = try fm.contentsOfDirectory(atPath: indexesDir)
    var totalSize = 0
    var totalDocuments = 0
    var documentTypes: [String: Int] = [:]

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    for file in files where file.hasSuffix(".json") {
      let filePath = joinPath(indexesDir, file)
      if let attrs = try? fm.attributesOfItem(atPath: filePath) {
        totalSize += (attrs[.size] as? Int) ?? 0
      }
      totalDocuments += 1

      if let data = try? Data(contentsOf: URL(fileURLWithPath: filePath)),
         let doc = try? decoder.decode(IndexedDocument.self, from: data)
      {
        let type = doc.metadata?.documentType.rawValue ?? "unknown"
        documentTypes[type, default: 0] += 1
      }
    }

    return (totalDocuments, totalSize, documentTypes)
  }

  public func clearCache() {
    cache.removeAll()
  }

  // MARK: - Private helpers

  private func generateId(_ name: String) -> String {
    let lowered = name.lowercased()
    let cleaned = lowered.replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
    let trimmed = cleaned.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    let result = String(trimmed.prefix(50))
    return result.isEmpty ? UUID().uuidString : result
  }

  private func getDocumentPath(_ id: String) -> String {
    joinPath(indexesDir, "\(id).json")
  }

  private func joinPath(_ base: String, _ component: String) -> String {
    URL(fileURLWithPath: base).appendingPathComponent(component).path
  }
}
