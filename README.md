# SwiftPageIndex

A vectorless RAG (Retrieval-Augmented Generation) library for Swift. It indexes documents into hierarchical trees and uses LLM reasoning to search them — no vector database required.

## How It Works

1. **Parse** a document (PDF, HTML, Markdown, or plain text) into sections
2. **Build** a hierarchical tree of sections with summaries
3. **Search** the tree using LLM-guided iterative traversal

The LLM navigates the tree top-down, selecting the most relevant branches at each level, drilling into children until it finds the answer. This replaces traditional vector similarity search with structured reasoning.

## Requirements

- Swift 6.2+
- macOS 15+ / iOS 18+ / Linux
- OpenAI API key (for LLM-powered features)

## Installation

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/user/SwiftPageIndex", branch: "main"),
]
```

Then add `"SwiftPageIndex"` to your target's dependencies.

## Configuration

### API Key

Provide the OpenAI API key in one of three ways (checked in order):

1. **Constructor parameter:**
```swift
let config = PageIndexConfig(openaiApiKey: "sk-...")
```

2. **Environment variable:**
```bash
export OPENAI_API_KEY=sk-...
```

3. **`.env` file** (loaded automatically from the working directory):
```
# .env
OPENAI_API_KEY=sk-...
```

The `.env` file supports `#` comments, blank lines, and quoted values. Existing environment variables are never overwritten.

To disable `.env` loading:
```swift
let config = PageIndexConfig(dotEnvPath: nil)
```

### Full Configuration

```swift
let config = PageIndexConfig(
    openaiApiKey: nil,           // defaults to OPENAI_API_KEY env var
    openaiModel: "gpt-4o-mini", // any OpenAI-compatible model
    dataDir: "./data",           // where indexes are stored on disk
    maxTokens: 4000              // max tokens per LLM call
)
```

## Usage

### Indexing Documents

```swift
let index = PageIndex(config: PageIndexConfig())

// From a local file
let doc = try await index.indexFromFile("report.pdf")

// From a URL
let doc = try await index.indexFromURL(URL(string: "https://example.com/doc.pdf")!)

// From raw data
let doc = try await index.indexContent(
    data,
    name: "my-document",
    contentType: "text/markdown"
)
```

#### Index Options

```swift
let options = IndexOptions(
    name: "quarterly-report",     // custom document name
    generateSummaries: true,      // generate section summaries (default: true)
    includeContent: false,        // store raw content in nodes (default: false)
    useLLMTreeBuilder: false      // use LLM for TOC extraction (default: false)
)

let doc = try await index.indexFromFile("report.pdf", options: options)
```

Set `useLLMTreeBuilder: true` for documents where heuristic header detection doesn't produce good results. The LLM tree builder sends content to the LLM to identify sections.

### Searching

```swift
let results = try await index.query("What was the revenue in Q4?")

for result in results {
    print("\(result.path.joined(separator: " > "))")
    print("  \(result.summary)")
    print("  Score: \(result.score)")
}
```

#### Search Options

```swift
let options = SearchOptions(
    topK: 5,                     // max results (default: 5)
    maxIterations: 5,            // max tree traversal depth (default: 5)
    confidenceThreshold: 0.5,    // min confidence to include (default: 0.5)
    includeReasoning: false      // include LLM reasoning in results (default: false)
)

let results = try await index.query(
    "revenue breakdown",
    documentIDs: ["quarterly-report"],  // search specific docs (nil = all)
    options: options
)
```

#### Search with Iteration Log

For debugging or transparency, use `queryWithLog` to see each step of the tree traversal:

```swift
let log = try await index.queryWithLog(
    "What is the company's guidance?",
    documentID: "quarterly-report"
)

for iteration in log.iterations {
    print("Iteration \(iteration.iteration):")
    print("  Evaluated: \(iteration.nodesEvaluated)")
    print("  Selected: \(iteration.selectedNodes)")
    print("  Confidence: \(iteration.confidence)")
    print("  Reasoning: \(iteration.reasoning)")
}
```

### Document Management

```swift
// List all indexed documents
let docs = try await index.listDocuments()

// Get a specific document
let doc = try await index.getDocument("quarterly-report")

// Get the tree structure
let tree = try await index.getDocumentTree("quarterly-report")

// Delete a document
let deleted = try await index.deleteDocument("quarterly-report")

// Stats
let stats = try await index.getStats()
print("Documents: \(stats.totalDocuments), Size: \(stats.totalSize) bytes")
```

### Inspecting Trees

```swift
if let tree = try await index.getDocumentTree("quarterly-report") {
    // Print tree structure
    print(index.printTree(tree))
    // [0000] Quarterly Report
    //   [0001] Financial Results
    //     [0002] Revenue
    //     [0003] Expenses
    //   [0004] Outlook

    // Get tree stats
    let stats = index.getTreeStats(tree)
    print("Nodes: \(stats.totalNodes), Depth: \(stats.maxDepth)")
}
```

## Supported Formats

| Format | Detection | Text Extraction | Section Detection |
|--------|-----------|----------------|-------------------|
| PDF | `%PDF-` header / MIME | PDFKit (macOS/iOS), empty on Linux | ALL CAPS headers, numbered sections |
| HTML | MIME / `<html` tag | SwiftSoup | `<h1>`-`<h6>` elements |
| Markdown | `.md` extension / `#` headers | Raw text | ATX (`#`) and setext (`===`/`---`) headers |
| Plain text | Fallback | Raw text | ALL CAPS, underlines, numbered sections |

## Architecture

```
PageIndex (facade)
  |
  |-- ParserFactory --> PDFParser / HTMLParser / MarkdownParser / TextParser
  |
  |-- TreeBuilder (heuristic, no LLM)
  |-- LLMTreeBuilder (LLM-powered TOC extraction)
  |
  |-- LLMTreeSearcher (iterative tree traversal with LLM)
  |
  |-- IndexManager (actor, JSON persistence + in-memory cache)
```

- All types are `Sendable` and safe for concurrent use
- `IndexManager` is an `actor` for thread-safe document storage
- LLM calls use `AnyLanguageModel` with `@Generable` types for structured responses
- JSON output uses `snake_case` keys for interoperability with the TypeScript version

## JSON Format

Indexed documents are stored as JSON files in `{dataDir}/indexes/`. The format is compatible with the TypeScript `pageindex-ts` library:

```json
{
  "doc_name": "quarterly-report",
  "id": "quarterly-report",
  "structure": [
    {
      "node_id": "0000",
      "title": "Quarterly Report",
      "summary": "Overview of Q4 financial results...",
      "start_index": 1,
      "end_index": 15,
      "nodes": [...]
    }
  ],
  "metadata": {
    "title": "Quarterly Report",
    "document_type": "pdf",
    "page_count": 15
  }
}
```

## Running Tests

```bash
swift test --enable-swift-testing --disable-xctest
```

## License

MIT
