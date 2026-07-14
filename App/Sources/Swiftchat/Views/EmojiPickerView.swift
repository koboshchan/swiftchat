import SwiftchatModels
import Observation
import SwiftUI

enum EmojiPickerSelection {
    case native(String)
    case custom(DiscordEmoji)

    var usageKey: String {
        switch self {
        case let .native(value): "unicode:\(value)"
        case let .custom(emoji): "custom:\(emoji.id)"
        }
    }
}

private struct LegacyEmojiPickerView: View {
    let model: AppModel
    let select: (EmojiPickerSelection) -> Void

    @State private var searchText = ""
    @State private var selectedSection: EmojiPickerSection = .native(.smileys)

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 0) {
                EmojiPickerSidebar(
                    guilds: model.snapshot?.guilds ?? [],
                    selectedSection: $selectedSection
                )
                Divider()
                VStack(alignment: .leading, spacing: 0) {
                    TextField("Search emojis", text: $searchText)
                        .textFieldStyle(.roundedBorder)
                        .padding(12)

                    EmojiPickerHeader(title: sectionTitle, count: filteredItems.count)

                    if isLoadingSelectedGuild {
                        Spacer()
                        ProgressView("Loading server emojis…")
                            .controlSize(.small)
                            .frame(maxWidth: .infinity)
                        Spacer()
                    } else if filteredItems.isEmpty {
                        ContentUnavailableView(
                            searchText.isEmpty ? "No emojis here" : "No matching emojis",
                            systemImage: "face.smiling",
                            description: Text(searchText.isEmpty ? "Choose another category." : "Try another emoji name.")
                        )
                    } else {
                        ScrollView {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 38, maximum: 44), spacing: 7)], spacing: 7) {
                                ForEach(filteredItems) { item in
                                    EmojiPickerButton(
                                        item: item,
                                        isFavorite: isFavorite(item),
                                        select: { choose(item) },
                                        toggleFavorite: { model.toggleFavoriteEmoji(item.usageKey) }
                                    )
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.bottom, 12)
                        }
                    }
                }
            }
            .padding(5)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .padding(6)
        .frame(width: 520, height: 420)
        .presentationBackground(.clear)
    }

    private var isLoadingSelectedGuild: Bool {
        guard case let .guild(guildID) = selectedSection else { return false }
        return model.loadingEmojiGuildIDs.contains(guildID)
    }

    private var sectionTitle: String {
        switch selectedSection {
        case .favorites: "Favorites"
        case .frequent: "Frequently Used"
        case let .native(category): category.title
        case let .guild(id): model.snapshot?.guilds.first(where: { $0.id == id })?.name ?? "Server Emojis"
        }
    }

    private var filteredItems: [EmojiPickerItem] {
        let allLoadedCustom = model.emojisByGuild.values.flatMap { $0 }.map(EmojiPickerItem.custom)
        let allNative = NativeEmojiCatalog.items.map(EmojiPickerItem.native)
        let items: [EmojiPickerItem] = switch selectedSection {
        case .favorites:
            (allNative + allLoadedCustom).filter { isFavorite($0) }
        case .frequent:
            (allNative + allLoadedCustom)
                .filter { usageScore($0) > 0 }
                .sorted { usageScore($0) > usageScore($1) }
                .prefix(80)
                .map { $0 }
        case let .native(category):
            NativeEmojiCatalog.items.filter { $0.category == category }.map(EmojiPickerItem.native)
        case let .guild(guildID):
            (model.emojisByGuild[guildID] ?? []).filter(\.isAvailable).map(EmojiPickerItem.custom)
        }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty ? items : items.filter { $0.matches(query) }
    }

    private func isFavorite(_ item: EmojiPickerItem) -> Bool {
        model.favoriteEmojiKeys.contains(item.usageKey)
            || model.discordFavoriteEmojiKeys.contains(item.discordKey)
    }

    private func usageScore(_ item: EmojiPickerItem) -> Int {
        model.emojiUsageCounts[item.usageKey, default: 0]
            + model.discordEmojiUsageScores[item.discordKey, default: 0]
    }

    private func choose(_ item: EmojiPickerItem) {
        let selection = item.selection
        model.recordEmojiUse(selection.usageKey)
        select(selection)
    }
}

private struct EmojiPickerHeader: View {
    let title: String
    let count: Int

    var body: some View {
        HStack {
            Text(title).font(.headline)
            Spacer()
            Text(count, format: .number).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
    }
}

private struct EmojiPickerSidebar: View {
    let guilds: [Guild]
    @Binding var selectedSection: EmojiPickerSection

    var body: some View {
        List(selection: $selectedSection) {
            Section {
                Label("Favorites", systemImage: "star.fill")
                    .labelStyle(.iconOnly)
                    .tag(EmojiPickerSection.favorites)
                    .help("Favorites")
                Label("Frequently Used", systemImage: "clock.fill")
                    .labelStyle(.iconOnly)
                    .tag(EmojiPickerSection.frequent)
                    .help("Frequently Used")
            }
            Section {
                ForEach(NativeEmojiCategory.allCases) { category in
                    Text(category.symbol)
                        .font(.title3)
                        .tag(EmojiPickerSection.native(category))
                        .help(category.title)
                }
            }
            Section {
                ForEach(guilds) { guild in
                    GuildEmojiSidebarIcon(guild: guild, isSelected: selectedSection == .guild(guild.id))
                        .tag(EmojiPickerSection.guild(guild.id))
                        .help(guild.name)
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .frame(width: 72)
    }
}

private struct GuildEmojiSidebarIcon: View {
    let guild: Guild
    let isSelected: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.3) : Color.secondary.opacity(0.12))
            if let url = guild.iconURL {
                AnimatedRemoteImage(url: url)
            } else {
                Text(guild.name.prefix(2).uppercased()).font(.caption.weight(.bold))
            }
        }
        .frame(width: 30, height: 30)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

private struct EmojiPickerButton: View {
    let item: EmojiPickerItem
    let isFavorite: Bool
    let select: () -> Void
    let toggleFavorite: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: select) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isHovering ? Color.primary.opacity(0.1) : .clear)
                item.preview
            }
            .frame(width: 38, height: 38, alignment: .center)
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(":\(item.name):")
        .contextMenu {
            Button(isFavorite ? "Remove from Favorites" : "Add to Favorites", action: toggleFavorite)
        }
    }
}

private enum EmojiPickerItem: Identifiable {
    case native(NativeEmoji)
    case custom(DiscordEmoji)

    var id: String { usageKey }
    var usageKey: String { selection.usageKey }
    var discordKey: String {
        switch self {
        case let .native(emoji): emoji.discordKey
        case let .custom(emoji): emoji.id
        }
    }
    var selection: EmojiPickerSelection {
        switch self {
        case let .native(emoji): .native(emoji.value)
        case let .custom(emoji): .custom(emoji)
        }
    }
    var name: String {
        switch self {
        case let .native(emoji): emoji.name
        case let .custom(emoji): emoji.name
        }
    }

    func matches(_ query: String) -> Bool {
        switch self {
        case let .native(emoji): emoji.searchText.localizedCaseInsensitiveContains(query)
        case let .custom(emoji): emoji.name.localizedCaseInsensitiveContains(query)
        }
    }

    @ViewBuilder var preview: some View {
        switch self {
        case let .native(emoji):
            Text(emoji.value)
                .font(.system(size: 31))
                .fixedSize()
                .frame(width: 36, height: 36, alignment: .center)
                .offset(y: -1)
        case let .custom(emoji):
            if let url = emoji.imageURL {
                if emoji.isAnimated {
                    AnimatedRemoteImage(url: url)
                        .frame(width: 34, height: 34)
                } else {
                    StaticEmojiImage(url: url)
                        .frame(width: 34, height: 34)
                }
            }
            else { Image(systemName: "face.dashed") }
        }
    }
}

private struct StaticEmojiImage: View {
    let url: URL

    var body: some View {
        AsyncImage(url: url, transaction: Transaction(animation: nil)) { phase in
            if case let .success(image) = phase {
                image
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                Color.clear
            }
        }
    }
}

private enum EmojiPickerSection: Hashable {
    case favorites
    case frequent
    case native(NativeEmojiCategory)
    case guild(GuildID)
}

private enum NativeEmojiCategory: String, CaseIterable, Identifiable {
    case smileys, people, nature, food, activities, travel, objects, symbols, flags

    var id: String { rawValue }
    var title: String {
        switch self {
        case .smileys: "Smileys & Emotion"
        case .people: "People & Body"
        case .nature: "Animals & Nature"
        case .food: "Food & Drink"
        case .activities: "Activities"
        case .travel: "Travel & Places"
        case .objects: "Objects"
        case .symbols: "Symbols"
        case .flags: "Flags"
        }
    }
    var symbol: String {
        switch self {
        case .smileys: "😀"
        case .people: "👋"
        case .nature: "🐻"
        case .food: "🍕"
        case .activities: "⚽️"
        case .travel: "🚗"
        case .objects: "💡"
        case .symbols: "❤️"
        case .flags: "🏳️"
        }
    }
}

private struct NativeEmoji: Identifiable {
    let value: String
    let name: String
    let aliases: String
    let category: NativeEmojiCategory
    var id: String { value }
    var searchText: String { "\(name) \(aliases)" }
    var discordKey: String {
        name.lowercased()
            .replacingOccurrences(of: "&", with: "and")
            .replacingOccurrences(of: "[^a-z0-9]+", with: "_", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    }

    var discordKeys: Set<String> {
        var keys = Set(aliases.split(separator: " ").map(String.init))
        keys.insert(discordKey)
        keys.insert(value)
        return keys
    }
}

private enum NativeEmojiCatalog {
    static let items: [NativeEmoji] = [
        .init(value: "😀", name: "grinning face", aliases: "smile happy", category: .smileys),
        .init(value: "😃", name: "grinning face with big eyes", aliases: "happy joy", category: .smileys),
        .init(value: "😄", name: "grinning squinting face", aliases: "laugh happy", category: .smileys),
        .init(value: "😁", name: "beaming face", aliases: "grin", category: .smileys),
        .init(value: "😆", name: "laughing face", aliases: "satisfied xd", category: .smileys),
        .init(value: "😅", name: "grinning face with sweat", aliases: "nervous relief", category: .smileys),
        .init(value: "😂", name: "face with tears of joy", aliases: "lol laugh cry", category: .smileys),
        .init(value: "🤣", name: "rolling on the floor laughing", aliases: "rofl", category: .smileys),
        .init(value: "😊", name: "smiling face with smiling eyes", aliases: "blush", category: .smileys),
        .init(value: "🙂", name: "slightly smiling face", aliases: "smile", category: .smileys),
        .init(value: "🙃", name: "upside down face", aliases: "sarcasm", category: .smileys),
        .init(value: "😉", name: "winking face", aliases: "wink", category: .smileys),
        .init(value: "😍", name: "smiling face with heart eyes", aliases: "love crush", category: .smileys),
        .init(value: "🥰", name: "smiling face with hearts", aliases: "love affection", category: .smileys),
        .init(value: "😘", name: "face blowing a kiss", aliases: "kiss", category: .smileys),
        .init(value: "😋", name: "face savoring food", aliases: "yum delicious", category: .smileys),
        .init(value: "😎", name: "smiling face with sunglasses", aliases: "cool", category: .smileys),
        .init(value: "🤩", name: "star struck", aliases: "excited wow", category: .smileys),
        .init(value: "🥳", name: "partying face", aliases: "celebrate birthday", category: .smileys),
        .init(value: "😏", name: "smirking face", aliases: "smirk", category: .smileys),
        .init(value: "😒", name: "unamused face", aliases: "annoyed", category: .smileys),
        .init(value: "😔", name: "pensive face", aliases: "sad", category: .smileys),
        .init(value: "😢", name: "crying face", aliases: "sad tear", category: .smileys),
        .init(value: "😭", name: "loudly crying face", aliases: "sob cry", category: .smileys),
        .init(value: "😤", name: "face with steam from nose", aliases: "triumph angry", category: .smileys),
        .init(value: "😡", name: "enraged face", aliases: "rage angry", category: .smileys),
        .init(value: "🤬", name: "face with symbols on mouth", aliases: "swearing curse", category: .smileys),
        .init(value: "🤯", name: "exploding head", aliases: "mind blown shocked", category: .smileys),
        .init(value: "😳", name: "flushed face", aliases: "embarrassed", category: .smileys),
        .init(value: "🥺", name: "pleading face", aliases: "puppy eyes", category: .smileys),
        .init(value: "🤔", name: "thinking face", aliases: "think hmm", category: .smileys),
        .init(value: "🫡", name: "saluting face", aliases: "salute respect", category: .smileys),
        .init(value: "🤗", name: "hugging face", aliases: "hug", category: .smileys),
        .init(value: "🫠", name: "melting face", aliases: "melt", category: .smileys),
        .init(value: "👀", name: "eyes", aliases: "look watch", category: .people),
        .init(value: "👋", name: "waving hand", aliases: "wave hello goodbye", category: .people),
        .init(value: "🤚", name: "raised back of hand", aliases: "hand", category: .people),
        .init(value: "🖐️", name: "hand with fingers splayed", aliases: "five", category: .people),
        .init(value: "✋", name: "raised hand", aliases: "stop high five", category: .people),
        .init(value: "👌", name: "ok hand", aliases: "okay", category: .people),
        .init(value: "🤌", name: "pinched fingers", aliases: "italian gesture", category: .people),
        .init(value: "🤏", name: "pinching hand", aliases: "small tiny", category: .people),
        .init(value: "✌️", name: "victory hand", aliases: "peace", category: .people),
        .init(value: "🤞", name: "crossed fingers", aliases: "luck hope", category: .people),
        .init(value: "🤟", name: "love you gesture", aliases: "ily", category: .people),
        .init(value: "🤘", name: "sign of the horns", aliases: "rock metal", category: .people),
        .init(value: "👉", name: "backhand index pointing right", aliases: "point right", category: .people),
        .init(value: "👈", name: "backhand index pointing left", aliases: "point left", category: .people),
        .init(value: "👆", name: "backhand index pointing up", aliases: "point up", category: .people),
        .init(value: "👇", name: "backhand index pointing down", aliases: "point down", category: .people),
        .init(value: "👍", name: "thumbs up", aliases: "+1 yes like", category: .people),
        .init(value: "👎", name: "thumbs down", aliases: "-1 no dislike", category: .people),
        .init(value: "👏", name: "clapping hands", aliases: "clap applause", category: .people),
        .init(value: "🙌", name: "raising hands", aliases: "hooray celebrate", category: .people),
        .init(value: "🫶", name: "heart hands", aliases: "love", category: .people),
        .init(value: "🙏", name: "folded hands", aliases: "pray thanks please", category: .people),
        .init(value: "💪", name: "flexed biceps", aliases: "strong muscle", category: .people),
        .init(value: "🧠", name: "brain", aliases: "smart mind", category: .people),
        .init(value: "🐶", name: "dog face", aliases: "puppy pet", category: .nature),
        .init(value: "🐱", name: "cat face", aliases: "kitty pet", category: .nature),
        .init(value: "🐭", name: "mouse face", aliases: "rodent", category: .nature),
        .init(value: "🐹", name: "hamster", aliases: "pet", category: .nature),
        .init(value: "🐰", name: "rabbit face", aliases: "bunny", category: .nature),
        .init(value: "🦊", name: "fox", aliases: "animal", category: .nature),
        .init(value: "🐻", name: "bear", aliases: "animal", category: .nature),
        .init(value: "🐼", name: "panda", aliases: "animal", category: .nature),
        .init(value: "🐨", name: "koala", aliases: "animal", category: .nature),
        .init(value: "🐯", name: "tiger face", aliases: "animal", category: .nature),
        .init(value: "🦁", name: "lion", aliases: "animal", category: .nature),
        .init(value: "🐸", name: "frog", aliases: "toad", category: .nature),
        .init(value: "🐵", name: "monkey face", aliases: "animal", category: .nature),
        .init(value: "🐔", name: "chicken", aliases: "bird", category: .nature),
        .init(value: "🐧", name: "penguin", aliases: "bird", category: .nature),
        .init(value: "🐦", name: "bird", aliases: "animal", category: .nature),
        .init(value: "🦄", name: "unicorn", aliases: "magic", category: .nature),
        .init(value: "🐝", name: "honeybee", aliases: "bee insect", category: .nature),
        .init(value: "🦋", name: "butterfly", aliases: "insect", category: .nature),
        .init(value: "🐌", name: "snail", aliases: "slow", category: .nature),
        .init(value: "🐙", name: "octopus", aliases: "sea", category: .nature),
        .init(value: "🦈", name: "shark", aliases: "blahaj sea", category: .nature),
        .init(value: "🌱", name: "seedling", aliases: "plant grow", category: .nature),
        .init(value: "🌸", name: "cherry blossom", aliases: "flower", category: .nature),
        .init(value: "🌈", name: "rainbow", aliases: "weather pride", category: .nature),
        .init(value: "☀️", name: "sun", aliases: "sunny weather", category: .nature),
        .init(value: "⭐️", name: "star", aliases: "favorite", category: .nature),
        .init(value: "🔥", name: "fire", aliases: "lit hot flame", category: .nature),
        .init(value: "🍏", name: "green apple", aliases: "fruit", category: .food),
        .init(value: "🍎", name: "red apple", aliases: "fruit", category: .food),
        .init(value: "🍓", name: "strawberry", aliases: "fruit", category: .food),
        .init(value: "🍕", name: "pizza", aliases: "food", category: .food),
        .init(value: "🍔", name: "hamburger", aliases: "burger food", category: .food),
        .init(value: "🍟", name: "french fries", aliases: "chips food", category: .food),
        .init(value: "🌮", name: "taco", aliases: "food", category: .food),
        .init(value: "🍿", name: "popcorn", aliases: "movie food", category: .food),
        .init(value: "🍪", name: "cookie", aliases: "biscuit", category: .food),
        .init(value: "🎂", name: "birthday cake", aliases: "cake party", category: .food),
        .init(value: "☕️", name: "hot beverage", aliases: "coffee tea", category: .food),
        .init(value: "🍺", name: "beer mug", aliases: "drink", category: .food),
        .init(value: "🍷", name: "wine glass", aliases: "drink", category: .food),
        .init(value: "⚽️", name: "soccer ball", aliases: "football sport", category: .activities),
        .init(value: "🏀", name: "basketball", aliases: "sport", category: .activities),
        .init(value: "🏈", name: "american football", aliases: "sport", category: .activities),
        .init(value: "🎾", name: "tennis", aliases: "sport", category: .activities),
        .init(value: "🎮", name: "video game", aliases: "controller gaming", category: .activities),
        .init(value: "🎲", name: "game die", aliases: "dice", category: .activities),
        .init(value: "🎯", name: "bullseye", aliases: "target dart", category: .activities),
        .init(value: "🎨", name: "artist palette", aliases: "art paint", category: .activities),
        .init(value: "🎸", name: "guitar", aliases: "music", category: .activities),
        .init(value: "🎉", name: "party popper", aliases: "celebrate tada", category: .activities),
        .init(value: "🏆", name: "trophy", aliases: "winner award", category: .activities),
        .init(value: "🚗", name: "automobile", aliases: "car vehicle", category: .travel),
        .init(value: "🚌", name: "bus", aliases: "vehicle", category: .travel),
        .init(value: "🚲", name: "bicycle", aliases: "bike", category: .travel),
        .init(value: "✈️", name: "airplane", aliases: "flight travel", category: .travel),
        .init(value: "🚀", name: "rocket", aliases: "space launch", category: .travel),
        .init(value: "🌍", name: "globe showing Europe Africa", aliases: "earth world", category: .travel),
        .init(value: "🏠", name: "house", aliases: "home", category: .travel),
        .init(value: "🏙️", name: "cityscape", aliases: "city", category: .travel),
        .init(value: "🌅", name: "sunrise", aliases: "morning", category: .travel),
        .init(value: "⌚️", name: "watch", aliases: "time", category: .objects),
        .init(value: "📱", name: "mobile phone", aliases: "iphone smartphone", category: .objects),
        .init(value: "💻", name: "laptop", aliases: "computer mac coding", category: .objects),
        .init(value: "⌨️", name: "keyboard", aliases: "computer typing", category: .objects),
        .init(value: "🖥️", name: "desktop computer", aliases: "monitor", category: .objects),
        .init(value: "📷", name: "camera", aliases: "photo", category: .objects),
        .init(value: "🎧", name: "headphone", aliases: "music audio", category: .objects),
        .init(value: "🔋", name: "battery", aliases: "power", category: .objects),
        .init(value: "💡", name: "light bulb", aliases: "idea", category: .objects),
        .init(value: "🔒", name: "locked", aliases: "secure lock", category: .objects),
        .init(value: "🔑", name: "key", aliases: "password", category: .objects),
        .init(value: "🛠️", name: "hammer and wrench", aliases: "tools build", category: .objects),
        .init(value: "🧪", name: "test tube", aliases: "science test", category: .objects),
        .init(value: "📌", name: "pushpin", aliases: "pin", category: .objects),
        .init(value: "❤️", name: "red heart", aliases: "love", category: .symbols),
        .init(value: "🧡", name: "orange heart", aliases: "love", category: .symbols),
        .init(value: "💛", name: "yellow heart", aliases: "love", category: .symbols),
        .init(value: "💚", name: "green heart", aliases: "love", category: .symbols),
        .init(value: "💙", name: "blue heart", aliases: "love", category: .symbols),
        .init(value: "💜", name: "purple heart", aliases: "love", category: .symbols),
        .init(value: "🖤", name: "black heart", aliases: "love", category: .symbols),
        .init(value: "💔", name: "broken heart", aliases: "sad heartbreak", category: .symbols),
        .init(value: "💕", name: "two hearts", aliases: "love", category: .symbols),
        .init(value: "💯", name: "hundred points", aliases: "100 perfect", category: .symbols),
        .init(value: "💢", name: "anger symbol", aliases: "mad", category: .symbols),
        .init(value: "💥", name: "collision", aliases: "boom explosion", category: .symbols),
        .init(value: "💫", name: "dizzy", aliases: "star", category: .symbols),
        .init(value: "✨", name: "sparkles", aliases: "shiny magic", category: .symbols),
        .init(value: "✅", name: "check mark button", aliases: "done yes", category: .symbols),
        .init(value: "❌", name: "cross mark", aliases: "no error", category: .symbols),
        .init(value: "⚠️", name: "warning", aliases: "alert", category: .symbols),
        .init(value: "❓", name: "question mark", aliases: "help", category: .symbols),
        .init(value: "‼️", name: "double exclamation mark", aliases: "important", category: .symbols),
        .init(value: "🏳️", name: "white flag", aliases: "surrender", category: .flags),
        .init(value: "🏴", name: "black flag", aliases: "flag", category: .flags),
        .init(value: "🏳️‍🌈", name: "rainbow flag", aliases: "pride lgbt", category: .flags),
        .init(value: "🏳️‍⚧️", name: "transgender flag", aliases: "trans pride", category: .flags),
        .init(value: "🇺🇦", name: "flag Ukraine", aliases: "ukraine ua", category: .flags),
        .init(value: "🇺🇸", name: "flag United States", aliases: "usa america", category: .flags),
        .init(value: "🇬🇧", name: "flag United Kingdom", aliases: "uk britain", category: .flags),
        .init(value: "🇪🇺", name: "flag European Union", aliases: "eu europe", category: .flags),
        .init(value: "🇯🇵", name: "flag Japan", aliases: "japan jp", category: .flags),
        .init(value: "🇨🇦", name: "flag Canada", aliases: "canada ca", category: .flags),
    ]
}

// The picker is a single document. The rail only bookmarks sections in that
// document, matching Discord's scrolling behavior instead of swapping pages.
struct EmojiPickerView: View {
    let model: AppModel
    let select: (EmojiPickerSelection) -> Void

    @State private var searchText = ""
    @State private var visibleSection: EmojiDocumentSection = .favorites

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            ScrollViewReader { proxy in
                HStack(spacing: 0) {
                    EmojiDocumentSidebar(
                        guilds: guilds,
                        visibleSection: visibleSection,
                        jump: { jump(to: $0, proxy: proxy) }
                    )

                    Divider()

                    VStack(alignment: .leading, spacing: 10) {
                        Label {
                            TextField("Search emojis", text: $searchText)
                                .textFieldStyle(.plain)
                        } icon: {
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 12)
                        .frame(height: 40)
                        .glassEffect(
                            .regular.tint(Color.white.opacity(0.055)).interactive(),
                            in: Capsule()
                        )
                        .padding(.horizontal, 12)
                        .padding(.top, 10)

                        ScrollView {
                            if query.isEmpty {
                                LazyVStack(alignment: .leading, spacing: 18) {
                                    documentSection(.favorites, items: favoriteItems)
                                    documentSection(.frequent, items: frequentItems)

                                    ForEach(guilds) { guild in
                                        documentSection(
                                            .guild(guild.id),
                                            items: guildItems(for: guild.id),
                                            isLoading: model.loadingEmojiGuildIDs.contains(guild.id),
                                            errorMessage: model.emojiLoadErrorsByGuild[guild.id]
                                        )
                                    }

                                    documentSection(.native, items: nativeItems)
                                }
                                .padding(.bottom, 14)
                            } else {
                                documentSection(.search, items: searchResults)
                                    .padding(.bottom, 14)
                            }
                        }
                        .scrollIndicators(.visible)
                    }
                }
                .padding(5)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .task {
                    proxy.scrollTo(EmojiDocumentSection.favorites, anchor: .top)
                    await model.loadDiscordEmojiSettings()
                    if let guildID = model.selectedGuildID {
                        await model.loadEmojis(for: guildID)
                    }
                    await Task.yield()
                    proxy.scrollTo(EmojiDocumentSection.favorites, anchor: .top)
                }
            }
        }
        .padding(6)
        .frame(width: 520, height: 420)
        .presentationBackground(.clear)
    }

    private var guilds: [Guild] { model.snapshot?.guilds ?? [] }

    private var nativeItems: [EmojiPickerItem] {
        NativeEmojiCatalog.items.map(EmojiPickerItem.native)
    }

    private var loadedCustomItems: [EmojiPickerItem] {
        model.emojisByGuild.values
            .flatMap { $0 }
            .filter(\.isAvailable)
            .map(EmojiPickerItem.custom)
    }

    private var allItems: [EmojiPickerItem] {
        let loadedIDs = Set(loadedCustomItems.compactMap { item -> String? in
            if case let .custom(emoji) = item { return emoji.id }
            return nil
        })
        return nativeItems + loadedCustomItems + unresolvedSettingsCustomItems(excluding: loadedIDs)
    }

    private func unresolvedSettingsCustomItems(excluding loadedIDs: Set<String>) -> [EmojiPickerItem] {
        var keys = model.discordFavoriteEmojiKeys
        keys.formUnion(model.discordEmojiUsageScores.keys)
        keys.formUnion(model.favoriteEmojiKeys.compactMap { key in
            key.hasPrefix("custom:") ? String(key.dropFirst("custom:".count)) : nil
        })
        keys.formUnion(model.emojiUsageCounts.keys.compactMap { key in
            key.hasPrefix("custom:") ? String(key.dropFirst("custom:".count)) : nil
        })

        return keys.compactMap { key in
            guard let id = customEmojiID(from: key), !loadedIDs.contains(id) else { return nil }
            return .custom(DiscordEmoji(
                id: id,
                name: customEmojiName(from: key),
                guildID: GuildID(rawValue: 0)
            ))
        }
    }

    private func customEmojiID(from key: String) -> String? {
        let candidate = key.split(separator: ":").last.map(String.init) ?? key
        return candidate.allSatisfy(\.isNumber) && !candidate.isEmpty ? candidate : nil
    }

    private func customEmojiName(from key: String) -> String {
        let components = key.split(separator: ":")
        guard components.count > 1 else { return "emoji" }
        return String(components[components.count - 2]).trimmingCharacters(in: CharacterSet(charactersIn: "<>"))
    }

    private var favoriteItems: [EmojiPickerItem] {
        allItems.filter(isFavorite)
    }

    private var frequentItems: [EmojiPickerItem] {
        allItems
            .filter { usageScore($0) > 0 }
            .sorted {
                let left = usageScore($0)
                let right = usageScore($1)
                return left == right ? $0.name < $1.name : left > right
            }
    }

    private func guildItems(for guildID: GuildID) -> [EmojiPickerItem] {
        (model.emojisByGuild[guildID] ?? [])
            .filter(\.isAvailable)
            .map(EmojiPickerItem.custom)
    }

    private var query: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var searchResults: [EmojiPickerItem] {
        allItems.filter { $0.matches(query) }
    }

    private func isFavorite(_ item: EmojiPickerItem) -> Bool {
        model.favoriteEmojiKeys.contains(item.usageKey)
            || !item.discordKeys.isDisjoint(with: model.discordFavoriteEmojiKeys)
    }

    private func usageScore(_ item: EmojiPickerItem) -> Int {
        model.emojiUsageCounts[item.usageKey, default: 0] + item.discordKeys.reduce(0) {
            max($0, model.discordEmojiUsageScores[$1, default: 0])
        }
    }

    private func choose(_ item: EmojiPickerItem) {
        let selection = item.selection
        model.recordEmojiUse(selection.usageKey)
        select(selection)
    }

    private func jump(to section: EmojiDocumentSection, proxy: ScrollViewProxy) {
        searchText = ""
        visibleSection = section
        Task { @MainActor in
            if case let .guild(guildID) = section {
                await model.loadEmojis(for: guildID)
            }
            await Task.yield()
            withAnimation(.snappy(duration: 0.3)) {
                proxy.scrollTo(section, anchor: .top)
            }
        }
    }

    @ViewBuilder
    private func documentSection(
        _ section: EmojiDocumentSection,
        items: [EmojiPickerItem],
        isLoading: Bool = false,
        errorMessage: String? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            EmojiPickerHeader(title: title(for: section), count: items.count)

            if isLoading && items.isEmpty {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Loading server emojis…")
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 42)
            } else if let errorMessage, items.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "wifi.exclamationmark")
                    Text("Couldn’t load these emojis.")
                    if case let .guild(guildID) = section {
                        Button("Retry") { Task { await model.retryEmojis(for: guildID) } }
                            .buttonStyle(.link)
                    }
                }
                .help(errorMessage)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 42)
            } else if items.isEmpty {
                Text(emptyMessage(for: section))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 38)
            } else {
                LazyVGrid(columns: gridColumns, alignment: .center, spacing: 2) {
                    ForEach(items) { item in
                        EmojiPickerButton(
                            item: item,
                            isFavorite: isFavorite(item),
                            select: { choose(item) },
                            toggleFavorite: { model.toggleFavoriteEmoji(item.usageKey) }
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 10)
            }
        }
        .id(section)
        .onAppear { visibleSection = section }
    }

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.fixed(38), spacing: 2, alignment: .center), count: 10)
    }

    private func title(for section: EmojiDocumentSection) -> String {
        switch section {
        case .favorites: "Favorites"
        case .frequent: "Frequently Used"
        case let .guild(id): guilds.first(where: { $0.id == id })?.name ?? "Server Emojis"
        case .native: "Emoji"
        case .search: "Search Results"
        }
    }

    private func emptyMessage(for section: EmojiDocumentSection) -> String {
        switch section {
        case .favorites: "Your favorite emojis will appear here."
        case .frequent: "Emojis you use will appear here."
        case .guild: "This server has no custom emojis."
        case .native: "No native emojis are available."
        case .search: "No emojis match “\(query)”."
        }
    }
}

private enum EmojiDocumentSection: Hashable {
    case favorites
    case frequent
    case guild(GuildID)
    case native
    case search
}

private struct EmojiDocumentSidebar: View {
    let guilds: [Guild]
    let visibleSection: EmojiDocumentSection
    let jump: (EmojiDocumentSection) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 7) {
                EmojiSidebarBookmark(
                    section: .favorites, visibleSection: visibleSection,
                    help: "Favorites", jump: jump
                ) { Image(systemName: "star.fill") }
                EmojiSidebarBookmark(
                    section: .frequent, visibleSection: visibleSection,
                    help: "Frequently Used", jump: jump
                ) { Image(systemName: "clock.fill") }

                Divider().padding(.horizontal, 8)

                ForEach(guilds) { guild in
                    EmojiSidebarBookmark(
                        section: .guild(guild.id), visibleSection: visibleSection,
                        help: guild.name, jump: jump
                    ) { EmojiGuildBookmarkIcon(guild: guild) }
                }

                Divider().padding(.horizontal, 8)

                EmojiSidebarBookmark(
                    section: .native, visibleSection: visibleSection,
                    help: "Native Emoji", jump: jump
                ) { Text("😀").font(.title3) }
            }
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .frame(width: 64)
    }
}

private struct EmojiSidebarBookmark<Content: View>: View {
    let section: EmojiDocumentSection
    let visibleSection: EmojiDocumentSection
    let help: String
    let jump: (EmojiDocumentSection) -> Void
    @ViewBuilder let content: () -> Content
    @State private var isHovering = false

    var body: some View {
        Button { jump(section) } label: {
            content()
                .frame(width: 34, height: 34, alignment: .center)
                .padding(4)
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .background {
            if visibleSection == section {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.accentColor.opacity(0.24))
            } else if isHovering {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(0.08))
            }
        }
        .onHover { isHovering = $0 }
        .help(help)
    }
}

private struct EmojiGuildBookmarkIcon: View {
    let guild: Guild

    var body: some View {
        Group {
            if let url = guild.iconURL {
                AnimatedRemoteImage(url: url)
            } else {
                Text(guild.name.prefix(2).uppercased())
                    .font(.caption.weight(.bold))
            }
        }
        .frame(width: 32, height: 32, alignment: .center)
        .background(Color.secondary.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private extension EmojiPickerItem {
    var discordKeys: Set<String> {
        switch self {
        case let .native(emoji): emoji.discordKeys
        case let .custom(emoji): [emoji.id]
        }
    }
}
