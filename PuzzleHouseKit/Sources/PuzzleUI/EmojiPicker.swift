import SwiftUI

/// Big-target emoji grid. Categoryed by category, searchable by keyword.
/// Bound `selection` updates and dismisses on tap.
public struct EmojiPicker: View {
    @Binding public var selection: String
    public let title: String
    @State private var query = ""
    @Environment(\.dismiss) private var dismiss

    public init(selection: Binding<String>, title: String = "Choose an emoji") {
        self._selection = selection
        self.title = title
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16, pinnedViews: [.sectionHeaders]) {
                    ForEach(visibleCategorys, id: \.title) { section in
                        SwiftUI.Section {
                            grid(section.emojis)
                        } header: {
                            Text(section.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal)
                                .padding(.vertical, 6)
                                .background(.thinMaterial)
                        }
                    }
                }
            }
            .searchable(text: $query, placement: searchPlacement, prompt: "Search")
            .navigationTitle(title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private var searchPlacement: SearchFieldPlacement {
        #if os(iOS)
        .navigationBarDrawer(displayMode: .always)
        #else
        .automatic
        #endif
    }

    private var visibleCategorys: [Category] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return Self.sections }
        return Self.sections.compactMap { section in
            let filtered = section.emojis.filter { entry in
                entry.keywords.contains(where: { $0.localizedCaseInsensitiveContains(q) })
            }
            return filtered.isEmpty ? nil : Category(title: section.title, emojis: filtered)
        }
    }

    @ViewBuilder
    private func grid(_ entries: [Entry]) -> some View {
        let columns = [GridItem(.adaptive(minimum: 56, maximum: 64), spacing: 8)]
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(entries, id: \.glyph) { entry in
                Button {
                    selection = entry.glyph
                    dismiss()
                } label: {
                    Text(entry.glyph)
                        .font(.system(size: 40))
                        .frame(width: 56, height: 56)
                }
                .buttonStyle(.plain)
                .background(
                    selection == entry.glyph
                        ? Color.accentColor.opacity(0.25)
                        : Color.clear,
                    in: RoundedRectangle(cornerRadius: 12)
                )
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Catalog

    public struct Entry: Hashable, Sendable {
        public let glyph: String
        public let keywords: [String]
        public init(_ glyph: String, _ keywords: [String]) {
            self.glyph = glyph
            self.keywords = keywords + [glyph]
        }
    }

    public struct Category: Hashable, Sendable {
        public let title: String
        public let emojis: [Entry]
    }

    public static let sections: [Category] = [
        .init(title: "Smileys", emojis: [
            .init("😀", ["smile", "happy"]), .init("😄", ["smile", "happy", "grin"]),
            .init("😁", ["grin", "beam"]), .init("😆", ["laugh"]),
            .init("😊", ["blush"]), .init("🥹", ["proud", "tear"]),
            .init("😍", ["love", "heart"]), .init("🥰", ["love", "hearts"]),
            .init("😘", ["kiss"]), .init("🤗", ["hug"]),
            .init("🤩", ["star", "wow"]), .init("🤓", ["nerd", "smart"]),
            .init("😎", ["cool", "sunglasses"]), .init("🥳", ["party"]),
            .init("😇", ["angel"]), .init("🙃", ["upside"]),
            .init("😴", ["sleep"]), .init("🤔", ["think"]),
            .init("🙄", ["roll", "eye"]), .init("😬", ["grimace"]),
        ]),
        .init(title: "Family", emojis: [
            .init("👨", ["man", "dad", "father"]), .init("👩", ["woman", "mom", "mother"]),
            .init("🧑", ["person"]), .init("👦", ["boy", "son"]),
            .init("👧", ["girl", "daughter"]), .init("👶", ["baby"]),
            .init("👴", ["grandpa", "old"]), .init("👵", ["grandma", "old"]),
            .init("🧓", ["older", "person"]),
            .init("👨‍🦰", ["man", "redhead"]), .init("👩‍🦰", ["woman", "redhead"]),
            .init("👨‍🦱", ["man", "curly"]), .init("👩‍🦱", ["woman", "curly"]),
            .init("👨‍🦳", ["man", "white", "hair"]), .init("👩‍🦳", ["woman", "white", "hair"]),
            .init("👨‍🦲", ["man", "bald"]), .init("👩‍🦲", ["woman", "bald"]),
            .init("🧔", ["beard"]), .init("👨‍💼", ["man", "office"]), .init("👩‍💼", ["woman", "office"]),
        ]),
        .init(title: "Animals", emojis: [
            .init("🐶", ["dog", "puppy"]), .init("🐱", ["cat", "kitten"]),
            .init("🐭", ["mouse"]), .init("🐹", ["hamster"]),
            .init("🐰", ["rabbit", "bunny"]), .init("🦊", ["fox"]),
            .init("🐻", ["bear"]), .init("🐼", ["panda"]),
            .init("🐨", ["koala"]), .init("🐯", ["tiger"]),
            .init("🦁", ["lion"]), .init("🐮", ["cow"]),
            .init("🐷", ["pig"]), .init("🐸", ["frog"]),
            .init("🐵", ["monkey"]), .init("🐔", ["chicken"]),
            .init("🐧", ["penguin"]), .init("🐦", ["bird"]),
            .init("🦆", ["duck"]), .init("🦉", ["owl"]),
            .init("🦋", ["butterfly"]), .init("🐝", ["bee"]),
            .init("🐙", ["octopus"]), .init("🦄", ["unicorn"]),
        ]),
        .init(title: "Food & drink", emojis: [
            .init("🍎", ["apple"]), .init("🍊", ["orange"]), .init("🍌", ["banana"]),
            .init("🍉", ["watermelon"]), .init("🍇", ["grapes"]), .init("🍓", ["strawberry"]),
            .init("🫐", ["blueberry"]), .init("🍒", ["cherry"]), .init("🥭", ["mango"]),
            .init("🍍", ["pineapple"]), .init("🥑", ["avocado"]), .init("🥕", ["carrot"]),
            .init("🌽", ["corn"]), .init("🍕", ["pizza"]), .init("🍔", ["burger"]),
            .init("🌮", ["taco"]), .init("🍣", ["sushi"]), .init("🍩", ["donut"]),
            .init("🍪", ["cookie"]), .init("🍰", ["cake"]), .init("🧁", ["cupcake"]),
            .init("🍫", ["chocolate"]), .init("☕", ["coffee"]), .init("🍵", ["tea"]),
            .init("🧋", ["boba"]), .init("🥤", ["drink"]),
        ]),
        .init(title: "Activities", emojis: [
            .init("⚽", ["soccer"]), .init("🏀", ["basketball"]), .init("🏈", ["football"]),
            .init("⚾", ["baseball"]), .init("🎾", ["tennis"]), .init("🏐", ["volleyball"]),
            .init("🎱", ["pool", "billiards"]), .init("🏓", ["pingpong"]),
            .init("🎯", ["dart", "target"]), .init("🎮", ["game", "video"]),
            .init("🎲", ["dice"]), .init("🧩", ["puzzle"]),
            .init("📚", ["book"]), .init("🎨", ["art"]),
            .init("🎵", ["music"]), .init("🎤", ["mic"]),
            .init("🎬", ["movie"]), .init("🏆", ["trophy"]),
            .init("🥇", ["gold", "first"]), .init("🥈", ["silver", "second"]),
            .init("🥉", ["bronze", "third"]),
        ]),
        .init(title: "Objects", emojis: [
            .init("🏠", ["house", "home"]), .init("🏡", ["house", "garden"]),
            .init("🏰", ["castle"]), .init("🚗", ["car"]),
            .init("🚙", ["suv"]), .init("🚕", ["taxi"]),
            .init("🚲", ["bike"]), .init("✈️", ["plane"]),
            .init("🚀", ["rocket"]), .init("⛵", ["boat", "sail"]),
            .init("📱", ["phone"]), .init("💻", ["laptop"]),
            .init("⌚", ["watch"]), .init("📷", ["camera"]),
            .init("💡", ["idea", "bulb"]), .init("🔑", ["key"]),
            .init("🔒", ["lock"]), .init("⏰", ["alarm"]),
            .init("📅", ["calendar"]),
        ]),
        .init(title: "Symbols", emojis: [
            .init("❤️", ["heart", "red"]), .init("🧡", ["heart", "orange"]),
            .init("💛", ["heart", "yellow"]), .init("💚", ["heart", "green"]),
            .init("💙", ["heart", "blue"]), .init("💜", ["heart", "purple"]),
            .init("🖤", ["heart", "black"]), .init("🤍", ["heart", "white"]),
            .init("✨", ["sparkles"]), .init("⭐", ["star"]),
            .init("🌟", ["star", "glowing"]), .init("🔥", ["fire"]),
            .init("💥", ["boom"]), .init("💯", ["100"]),
            .init("⚡", ["bolt", "lightning"]), .init("☀️", ["sun"]),
            .init("🌈", ["rainbow"]), .init("🌙", ["moon"]),
            .init("🎉", ["party", "popper"]), .init("🎊", ["confetti"]),
        ]),
    ]
}
