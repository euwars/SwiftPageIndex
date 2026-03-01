import Foundation

public enum ParserFactory {
  public static func getParser(content: Data, mimeType: String?, llm: PageIndexLLM? = nil) -> any DocumentParser {
    let parsers: [any DocumentParser] = [
      PDFParser(llm: llm),
      HTMLParser(),
      MarkdownParser(),
      TextParser(),
    ]

    for parser in parsers {
      if parser.canParse(content: content, mimeType: mimeType) {
        return parser
      }
    }

    return parsers.last!
  }

  public static func getParserByType(_ type: DocumentType, llm: PageIndexLLM? = nil) -> any DocumentParser {
    switch type {
    case .pdf: PDFParser(llm: llm)
    case .html: HTMLParser()
    case .markdown: MarkdownParser()
    case .text: TextParser()
    }
  }

  public static func documentTypeFromExtension(_ filename: String) -> DocumentType? {
    let ext = filename.lowercased().components(separatedBy: ".").last ?? ""
    switch ext {
    case "pdf": return .pdf
    case "html", "htm": return .html
    case "md", "markdown": return .markdown
    case "txt", "text": return .text
    default: return nil
    }
  }

  public static func documentTypeFromMime(_ mimeType: String) -> DocumentType? {
    let mime = mimeType.lowercased()
    if mime.contains("pdf") { return .pdf }
    if mime.contains("html") { return .html }
    if mime.contains("markdown") { return .markdown }
    if mime.contains("text/plain") { return .text }
    return nil
  }
}
