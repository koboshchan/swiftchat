import SwiftUI

public struct MessageBodyView: View {
    private let content: String

    public init(content: String) { self.content = content }

    public var body: some View {
        Text(MarkdownRenderCache.shared.attributedString(for: content))
            .lineSpacing(1)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

@MainActor
private final class MarkdownRenderCache {
    static let shared = MarkdownRenderCache()

    private let values = NSCache<NSString, AttributedStringBox>()

    private init() {
        values.countLimit = 1_000
        values.totalCostLimit = 8 * 1_024 * 1_024
    }

    func attributedString(for source: String) -> AttributedString {
        let key = source as NSString
        if let cached = values.object(forKey: key) { return cached.value }
        let value = DiscordMarkdown.attributed(source)
        values.setObject(AttributedStringBox(value), forKey: key, cost: source.utf8.count)
        return value
    }
}

private final class AttributedStringBox: NSObject {
    let value: AttributedString

    init(_ value: AttributedString) {
        self.value = value
    }
}
