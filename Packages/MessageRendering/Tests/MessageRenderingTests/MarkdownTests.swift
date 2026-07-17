@testable import MessageRendering
import Testing

@Test func `markdown removes delimiters`() {
    let value = DiscordMarkdown.attributed("Hello **native** `client`")
    #expect(String(value.characters) == "Hello native client")
}

@Test func `discord markdown preserves compact line breaks and styles headings`() {
    let value = DiscordMarkdown.attributed("*markdown*\n**bold**\n`code`\n# heading")
    #expect(String(value.characters) == "markdown\nbold\ncode\nheading")
    #expect(String(value.characters).filter { $0 == "\n" }.count == 3)
}
