import SwiftUI

struct InlineText: View {
  @Environment(\.inlineImageProvider) private var inlineImageProvider
  @Environment(\.baseURL) private var baseURL
  @Environment(\.imageBaseURL) private var imageBaseURL
  @Environment(\.softBreakMode) private var softBreakMode
  @Environment(\.theme) private var theme

  @State private var inlineImages: [String: Image] = [:]

  private let inlines: [InlineNode]

  init(_ inlines: [InlineNode]) {
    self.inlines = inlines
  }

  var body: some View {
    TextStyleAttributesReader { attributes in
      let views = self.renderViews(attributes: attributes)
      if #available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *) {
        FlowLayout(horizontalSpacing: 0, verticalSpacing: 0) {
          ForEach(Array(views.indices), id: \.self) { index in
            views[index]
          }
        }
      } else {
        HStack(spacing: 0) {
          ForEach(Array(views.indices), id: \.self) { index in
            views[index]
          }
        }
      }
    }
    .task(id: self.inlines) {
      self.inlineImages = (try? await self.loadInlineImages()) ?? [:]
    }
  }

  private func loadInlineImages() async throws -> [String: Image] {
    let images = Set(self.inlines.compactMap(\.imageData))
    guard !images.isEmpty else { return [:] }

    return try await withThrowingTaskGroup(of: (String, Image).self) { taskGroup in
      for image in images {
        guard let url = URL(string: image.source, relativeTo: self.imageBaseURL) else {
          continue
        }

        taskGroup.addTask {
          (image.source, try await self.inlineImageProvider.image(with: url, label: image.alt))
        }
      }

      var inlineImages: [String: Image] = [:]

      for try await result in taskGroup {
        inlineImages[result.0] = result.1
      }

      return inlineImages
    }
  }

  private func renderViews(attributes: AttributeContainer) -> [AnyView] {
    var renderer = InlineViewRenderer(
      baseURL: self.baseURL,
      textStyles: .init(
        code: self.theme.code,
        emphasis: self.theme.emphasis,
        strong: self.theme.strong,
        strikethrough: self.theme.strikethrough,
        link: self.theme.link
      ),
      images: self.inlineImages,
      softBreakMode: self.softBreakMode,
      attributes: attributes,
      theme: self.theme
    )
    renderer.render(self.inlines)
    return renderer.result
  }
}

private struct InlineViewRenderer {
  var result: [AnyView] = []
  private var pendingText: Text?

  private let baseURL: URL?
  private let textStyles: InlineTextStyles
  private let images: [String: Image]
  private let softBreakMode: SoftBreak.Mode
  private var attributes: AttributeContainer
  private let theme: Theme
  private var shouldSkipNextWhitespace = false

  init(
    baseURL: URL?,
    textStyles: InlineTextStyles,
    images: [String: Image],
    softBreakMode: SoftBreak.Mode,
    attributes: AttributeContainer,
    theme: Theme
  ) {
    self.baseURL = baseURL
    self.textStyles = textStyles
    self.images = images
    self.softBreakMode = softBreakMode
    self.attributes = attributes
    self.theme = theme
  }

  mutating func render<S: Sequence>(_ inlines: S) where S.Element == InlineNode {
    for inline in inlines { self.render(inline) }
    self.flushText()
  }

  private mutating func render(_ inline: InlineNode) {
    switch inline {
    case .text(let content):
      self.renderText(content)
    case .softBreak:
      self.renderSoftBreak()
    case .lineBreak:
      self.renderLineBreak()
    case .code(let content):
      self.flushText()
      self.renderCode(content)
    case .html(let content):
      self.renderHTML(content)
    case .emphasis(let children):
      self.renderEmphasis(children: children)
    case .strong(let children):
      self.renderStrong(children: children)
    case .strikethrough(let children):
      self.renderStrikethrough(children: children)
    case .link(let destination, let children):
      self.renderLink(destination: destination, children: children)
    case .image(let source, _):
      self.flushText()
      self.renderImage(source)
    }
  }

  private mutating func renderText(_ text: String) {
    var text = text

    if self.shouldSkipNextWhitespace {
      self.shouldSkipNextWhitespace = false
      text = text.replacingOccurrences(of: "^\\s+", with: "", options: .regularExpression)
    }

    self.appendText(
      Text(
        InlineNode.text(text).renderAttributedString(
          baseURL: self.baseURL,
          textStyles: self.textStyles,
          softBreakMode: self.softBreakMode,
          attributes: self.attributes
        )
      )
    )
  }

  private mutating func renderSoftBreak() {
    switch self.softBreakMode {
    case .space where self.shouldSkipNextWhitespace:
      self.shouldSkipNextWhitespace = false
    case .space:
      self.appendText(
        Text(
          InlineNode.softBreak.renderAttributedString(
            baseURL: self.baseURL,
            textStyles: self.textStyles,
            softBreakMode: self.softBreakMode,
            attributes: self.attributes
          )
        )
      )
    case .lineBreak:
      self.shouldSkipNextWhitespace = true
      self.appendText(
        Text(
          InlineNode.lineBreak.renderAttributedString(
            baseURL: self.baseURL,
            textStyles: self.textStyles,
            softBreakMode: self.softBreakMode,
            attributes: self.attributes
          )
        )
      )
    }
  }

  private mutating func renderLineBreak() {
    self.appendText(
      Text(
        InlineNode.lineBreak.renderAttributedString(
          baseURL: self.baseURL,
          textStyles: self.textStyles,
          softBreakMode: self.softBreakMode,
          attributes: self.attributes
        )
      )
    )
  }

  private mutating func renderCode(_ code: String) {
    let view = InlineCodeView(
      text: code,
      backgroundColor: self.theme.codeBackgroundColor ?? self.attributes.backgroundColor,
      cornerRadius: self.theme.codeCornerRadius,
      textStyle: self.textStyles.code
    )
    self.result.append(AnyView(view))
  }

  private mutating func renderHTML(_ html: String) {
    let tag = HTMLTag(html)

    switch tag?.name.lowercased() {
    case "br":
      self.appendText(
        Text(
          InlineNode.lineBreak.renderAttributedString(
            baseURL: self.baseURL,
            textStyles: self.textStyles,
            softBreakMode: self.softBreakMode,
            attributes: self.attributes
          )
        )
      )
      self.shouldSkipNextWhitespace = true
    default:
      self.renderText(html)
    }
  }

  private mutating func renderEmphasis(children: [InlineNode]) {
    let savedAttributes = self.attributes
    self.attributes = self.textStyles.emphasis.mergingAttributes(self.attributes)

    for child in children {
      self.render(child)
    }

    self.attributes = savedAttributes
  }

  private mutating func renderStrong(children: [InlineNode]) {
    let savedAttributes = self.attributes
    self.attributes = self.textStyles.strong.mergingAttributes(self.attributes)

    for child in children {
      self.render(child)
    }

    self.attributes = savedAttributes
  }

  private mutating func renderStrikethrough(children: [InlineNode]) {
    let savedAttributes = self.attributes
    self.attributes = self.textStyles.strikethrough.mergingAttributes(self.attributes)

    for child in children {
      self.render(child)
    }

    self.attributes = savedAttributes
  }

  private mutating func renderLink(destination: String, children: [InlineNode]) {
    let savedAttributes = self.attributes
    self.attributes = self.textStyles.link.mergingAttributes(self.attributes)
    self.attributes.link = URL(string: destination, relativeTo: self.baseURL)

    for child in children {
      self.render(child)
    }

    self.attributes = savedAttributes
  }

  private mutating func renderImage(_ source: String) {
    if let image = self.images[source] {
      self.result.append(AnyView(image))
    }
  }

  private mutating func appendText(_ text: Text) {
    if let current = self.pendingText {
      self.pendingText = current + text
    } else {
      self.pendingText = text
    }
  }

  private mutating func flushText() {
    if let text = self.pendingText {
      self.result.append(AnyView(text))
      self.pendingText = nil
    }
  }
}
