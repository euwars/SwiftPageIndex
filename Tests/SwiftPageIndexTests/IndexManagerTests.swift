import Foundation
@testable import SwiftPageIndex
import Testing

@Suite("IndexManager Tests")
struct IndexManagerTests {
  func makeTempDir() -> String {
    let tempDir = NSTemporaryDirectory() + "SwiftPageIndexTests-\(UUID().uuidString)"
    try? FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
    return tempDir
  }

  @Test("Save and retrieve document")
  func saveAndGet() async throws {
    let tempDir = makeTempDir()
    defer { try? FileManager.default.removeItem(atPath: tempDir) }

    let manager = IndexManager(dataDir: tempDir)
    let tree = [TreeNode(nodeId: "0000", title: "Root", summary: "Summary", startIndex: 1, endIndex: 1, nodes: [])]
    let metadata = DocumentMetadata(title: "Test Doc", documentType: .markdown)

    let saved = try await manager.save(name: "test-document", tree: tree, metadata: metadata)
    #expect(saved.docName == "test-document")
    #expect(saved.id != nil)

    let retrieved = try await manager.get(#require(saved.id))
    #expect(retrieved != nil)
    #expect(retrieved?.docName == "test-document")
    #expect(retrieved?.structure.count == 1)
    #expect(retrieved?.structure[0].nodeId == "0000")
  }

  @Test("List documents")
  func listDocuments() async throws {
    let tempDir = makeTempDir()
    defer { try? FileManager.default.removeItem(atPath: tempDir) }

    let manager = IndexManager(dataDir: tempDir)
    let tree = [TreeNode(nodeId: "0000", title: "Root", summary: "", startIndex: 1, endIndex: 1, nodes: [])]

    _ = try await manager.save(name: "doc-one", tree: tree, metadata: DocumentMetadata(documentType: .text))
    _ = try await manager.save(name: "doc-two", tree: tree, metadata: DocumentMetadata(documentType: .html))

    let list = try await manager.list()
    #expect(list.count == 2)
  }

  @Test("Delete document")
  func deleteDocument() async throws {
    let tempDir = makeTempDir()
    defer { try? FileManager.default.removeItem(atPath: tempDir) }

    let manager = IndexManager(dataDir: tempDir)
    let tree = [TreeNode(nodeId: "0000", title: "Root", summary: "", startIndex: 1, endIndex: 1, nodes: [])]

    let saved = try await manager.save(name: "to-delete", tree: tree, metadata: DocumentMetadata(documentType: .text))
    let deleted = try await manager.delete(#require(saved.id))
    #expect(deleted)

    let retrieved = try await manager.get(#require(saved.id))
    #expect(retrieved == nil)
  }

  @Test("ID generation is deterministic and URL-safe")
  func idGeneration() async throws {
    let tempDir = makeTempDir()
    defer { try? FileManager.default.removeItem(atPath: tempDir) }

    let manager = IndexManager(dataDir: tempDir)
    let tree = [TreeNode(nodeId: "0000", title: "R", summary: "", startIndex: 1, endIndex: 1, nodes: [])]

    let doc1 = try await manager.save(name: "My Document!", tree: tree, metadata: DocumentMetadata(documentType: .text))
    #expect(doc1.id == "my-document")

    let doc2 = try await manager.save(
      name: "CREE8 Investor 2026 v1",
      tree: tree,
      metadata: DocumentMetadata(documentType: .pdf),
    )
    #expect(doc2.id == "cree8-investor-2026-v1")
  }

  @Test("JSON output format matches TS")
  func jsonFormat() async throws {
    let tempDir = makeTempDir()
    defer { try? FileManager.default.removeItem(atPath: tempDir) }

    let manager = IndexManager(dataDir: tempDir)
    let tree = [TreeNode(
      nodeId: "0000", title: "Test", summary: "Summary",
      startIndex: 1, endIndex: 5,
      nodes: [TreeNode(
        nodeId: "0001",
        title: "Child",
        summary: "Child summary",
        startIndex: 2,
        endIndex: 3,
        nodes: [],
      )],
    )]

    let saved = try await manager.save(
      name: "json-test",
      tree: tree,
      metadata: DocumentMetadata(title: "Test", documentType: .markdown),
    )

    let indexesDir = URL(fileURLWithPath: tempDir).appendingPathComponent("indexes").path
    let filePath = URL(fileURLWithPath: indexesDir).appendingPathComponent("\(saved.id!).json").path
    let jsonData = try Data(contentsOf: URL(fileURLWithPath: filePath))
    let json = try #require(String(data: jsonData, encoding: .utf8))

    #expect(json.contains("\"doc_name\""))
    #expect(json.contains("\"node_id\""))
    #expect(json.contains("\"start_index\""))
    #expect(json.contains("\"end_index\""))
    #expect(!json.contains("\"docName\""))
    #expect(!json.contains("\"nodeId\""))
  }

  @Test("Update document")
  func updateDocument() async throws {
    let tempDir = makeTempDir()
    defer { try? FileManager.default.removeItem(atPath: tempDir) }

    let manager = IndexManager(dataDir: tempDir)
    let tree = [TreeNode(nodeId: "0000", title: "Root", summary: "", startIndex: 1, endIndex: 1, nodes: [])]

    let saved = try await manager.save(name: "updatable", tree: tree, metadata: DocumentMetadata(documentType: .text))

    let newTree = [TreeNode(
      nodeId: "0000",
      title: "Updated Root",
      summary: "New",
      startIndex: 1,
      endIndex: 2,
      nodes: [],
    )]
    let updated = try await manager.update(#require(saved.id), structure: newTree)

    #expect(updated?.structure[0].title == "Updated Root")
  }

  @Test("GetStats returns correct counts")
  func getStats() async throws {
    let tempDir = makeTempDir()
    defer { try? FileManager.default.removeItem(atPath: tempDir) }

    let manager = IndexManager(dataDir: tempDir)
    let tree = [TreeNode(nodeId: "0000", title: "R", summary: "", startIndex: 1, endIndex: 1, nodes: [])]

    _ = try await manager.save(name: "s1", tree: tree, metadata: DocumentMetadata(documentType: .pdf))
    _ = try await manager.save(name: "s2", tree: tree, metadata: DocumentMetadata(documentType: .pdf))
    _ = try await manager.save(name: "s3", tree: tree, metadata: DocumentMetadata(documentType: .html))

    let stats = try await manager.getStats()
    #expect(stats.totalDocuments == 3)
    #expect(stats.documentTypes["pdf"] == 2)
    #expect(stats.documentTypes["html"] == 1)
  }
}
