import SwiftUI

/// The properties of an inline code element.
///
/// The ``Theme/inlineCode`` inline style receives a `CodeInlineConfiguration`
/// value in its body closure.
public struct CodeInlineConfiguration {
  /// A type-erased view of an inline code element.
  public struct Label: View {
    init<L: View>(_ label: L) {
      self.body = AnyView(label)
    }

    public let body: AnyView
  }

  /// The code string displayed by the inline code element.
  public let text: String

  /// The default inline code view.
  public let label: Label
}
