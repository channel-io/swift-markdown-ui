import SwiftUI

/// The properties of a Markdown link inline element.
///
/// The ``Theme/inlineLink`` inline style receives a `LinkInlineConfiguration`
/// value in its body closure.
public struct LinkInlineConfiguration {
  /// A type-erased view of a link label.
  public struct Label: View {
    init<L: View>(_ label: L) {
      self.body = AnyView(label)
    }

    public let body: AnyView
  }

  /// The link destination URL string.
  public let destination: String

  /// The plain text contents of the link.
  public let text: String

  /// The default link view.
  public let label: Label
}
