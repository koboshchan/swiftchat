import Testing
@testable import MessageRendering

@Test func markdownRemovesDelimiters() {
    let value = DiscordMarkdown.attributed("Hello **native** `client`")
    #expect(String(value.characters) == "Hello native client")
}

@Test func discordMarkdownPreservesCompactLineBreaksAndStylesHeadings() {
    let value = DiscordMarkdown.attributed("*markdown*\n**bold**\n`code`\n# heading")
    #expect(String(value.characters) == "markdown\nbold\ncode\nheading")
    #expect(String(value.characters).filter { $0 == "\n" }.count == 3)
}
