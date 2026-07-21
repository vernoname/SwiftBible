import SwiftUI

// MARK: - Main SwiftBible struct
public struct SwiftBible {
    static let apiBaseURL = "https://bible.api.historicvernoname.church"

    public static func fetchVerses(reference: String, translation: String = "NIV") async throws -> [BibleVerse] {
        guard let parsed = ParsedBibleReference.parse(reference) else {
            throw BibleError.invalidReference
        }
        return try await fetchVerses(parsed: parsed, translation: translation)
    }

    public static func fetchVerses(book: String, chapter: String, verse: String, translation: String = "NIV") async throws -> [BibleVerse] {
        let reference = verse.isEmpty ? "\(book) \(chapter)" : "\(book) \(chapter):\(verse)"
        return try await fetchVerses(reference: reference, translation: translation)
    }

    private static func fetchVerses(parsed: ParsedBibleReference, translation: String) async throws -> [BibleVerse] {
        let lookup = try await BibleLookupStore.shared.lookup()

        guard let translationInfo = lookup.translations[translation] else {
            throw BibleError.invalidTranslation
        }

        guard let bookId = translationInfo.bookId(named: parsed.book) else {
            throw BibleError.invalidBook
        }

        guard let bookInfo = translationInfo.books[String(bookId)] else {
            throw BibleError.invalidBook
        }
        let bookName = bookInfo.name

        guard bookInfo.chapters[String(parsed.startChapter)] != nil,
              let endChapterInfo = bookInfo.chapters[String(parsed.endChapter)] else {
            throw BibleError.invalidChapter
        }

        let startVerse = parsed.startVerse ?? 1
        let endVerse = parsed.endVerse ?? endChapterInfo.verseCount

        var result: [BibleVerse] = []
        for chapterNumber in parsed.startChapter...parsed.endChapter {
            guard let chapterInfo = bookInfo.chapters[String(chapterNumber)] else {
                throw BibleError.invalidChapter
            }

            let lowerBound = chapterNumber == parsed.startChapter ? startVerse : 1
            let upperBound = chapterNumber == parsed.endChapter ? endVerse : chapterInfo.verseCount

            let verses = try await fetchChapter(translation: translation, bookName: bookName, chapter: chapterNumber)
            let filtered = verses.filter { $0.verseId >= lowerBound && $0.verseId <= upperBound }
            result.append(contentsOf: filtered.map {
                BibleVerse(id: $0.id, bookId: $0.book.id, chapterId: $0.chapterId, verseId: $0.verseId, text: $0.verse)
            })
        }
        return result
    }

    private static func fetchChapter(translation: String, bookName: String, chapter: Int) async throws -> [VerseResponse] {
        guard let encodedBookName = bookName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            throw BibleError.invalidURL
        }
        let urlString = "\(apiBaseURL)/\(translation)/\(encodedBookName)/\(chapter).json"
        guard let url = URL(string: urlString) else {
            throw BibleError.invalidURL
        }

        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode([VerseResponse].self, from: data)
    }
}

// MARK: - Models
public struct BibleVerse: Identifiable, Codable, Sendable, Equatable {
    public let id: Int
    public let bookId: Int
    public let chapterId: Int
    public let verseId: Int
    public let text: String

    public init(id: Int, bookId: Int, chapterId: Int, verseId: Int, text: String) {
        self.id = id
        self.bookId = bookId
        self.chapterId = chapterId
        self.verseId = verseId
        self.text = text
    }
}

struct BibleVersion: Hashable, Sendable {
    let name: String
    let id: String
}

struct VerseResponse: Codable, Sendable {
    let id: Int
    let book: Book
    let chapterId: Int
    let verseId: Int
    let verse: String
}

struct Book: Codable {
    let id: Int
    let name: String
    let testament: String
}

// MARK: - Views
public struct BibleVersePickerView<ButtonContent: View>: View {
    @Binding var selectedVerses: [BibleVerse]
    @State private var isPresented = false
    private let buttonContent: (() -> ButtonContent)?

    public init(selectedVerses: Binding<[BibleVerse]>) where ButtonContent == Text {
        self._selectedVerses = selectedVerses
        self.buttonContent = nil
    }

    public init(selectedVerses: Binding<[BibleVerse]>, @ViewBuilder buttonContent: @escaping () -> ButtonContent) {
        self._selectedVerses = selectedVerses
        self.buttonContent = buttonContent
    }

    public var body: some View {
        Button(action: {
            isPresented = true
        }) {
            if let customContent = buttonContent {
                customContent()
            } else {
                defaultButtonContent
            }
        }
        .sheet(isPresented: $isPresented) {
            BibleVersePicker(selectedVerses: $selectedVerses)
        }
    }

    private var defaultButtonContent: some View {
        Text("Select Bible Verse")
            .padding()
            .background(Color.blue)
            .foregroundColor(.white)
            .cornerRadius(8)
    }
}

struct BibleVersePicker: View, Sendable {
    @State private var availableVersions: [BibleVersion] = []
    @State private var selectedVersion = BibleVersion(name: "New International Version", id: "NIV")
    @State private var verseReference = ""
    @State private var book = ""
    @State private var chapter = ""
    @State private var verse = ""
    @State private var verseContent: [BibleVerse] = []
    @Binding var selectedVerses: [BibleVerse]
    @State private var isLoading = false
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            List {
                Section(header: Text("Bible Version")) {
                    Picker("Version", selection: $selectedVersion) {
                        ForEach(availableVersions, id: \.id) { version in
                            Text(version.name).tag(version)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                }

                Section(header: Text("Verse Reference")) {
                    TextField("e.g., John 3:16 or Romans 8:28-30", text: $verseReference)
                        .onChange(of: verseReference) { _ in
                            parseVerseReference()
                        }

                    if !book.isEmpty {
                        Text("Book: \(book)")
                    }
                    if !chapter.isEmpty {
                        Text("Chapter: \(chapter)")
                    }
                    if !verse.isEmpty {
                        Text("Verse(s): \(verse)")
                    }
                }

                Section(header: Text("Verses")) {
                    if isLoading {
                        ProgressView()
                    } else {
                        ForEach(verseContent) { verse in
                            Text("\(verse.verseId). \(verse.text)")
                        }
                    }
                }
            }
            #if !os(macOS)
            .listStyle(InsetGroupedListStyle())
            #endif
            .navigationTitle("Select Bible Verse")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        selectedVerses = verseContent
                        dismiss()
                    }
                }
            }
        }
        #if !os(macOS)
        .navigationViewStyle(StackNavigationViewStyle())
        #endif
        .task {
            await loadAvailableVersions()
        }
    }

    private func loadAvailableVersions() async {
        do {
            let lookup = try await BibleLookupStore.shared.lookup()
            let versions = lookup.translations
                .map { BibleVersion(name: $0.value.name, id: $0.key) }
                .sorted { $0.name < $1.name }
            availableVersions = versions

            if let currentSelection = versions.first(where: { $0.id == selectedVersion.id }) {
                selectedVersion = currentSelection
            } else if let firstVersion = versions.first {
                selectedVersion = firstVersion
            }
        } catch {
            print("Error loading Bible versions: \(error)")
        }
    }

    private func parseVerseReference() {
        guard let parsed = ParsedBibleReference.parse(verseReference) else {
            book = ""
            chapter = ""
            verse = ""
            return
        }

        book = parsed.book
        chapter = parsed.endChapter == parsed.startChapter
            ? "\(parsed.startChapter)"
            : "\(parsed.startChapter)-\(parsed.endChapter)"

        switch (parsed.startVerse, parsed.endVerse) {
        case (nil, _):
            verse = ""
        case (let start?, let end?) where start == end:
            verse = "\(start)"
        case (let start?, let end?):
            verse = "\(start)-\(end)"
        case (let start?, nil):
            verse = "\(start)"
        }

        fetchVerses()
    }

    private func fetchVerses() {
        isLoading = true
        Task {
            do {
                verseContent = try await SwiftBible.fetchVerses(reference: verseReference, translation: selectedVersion.id)
            } catch {
                print("Error fetching verses: \(error)")
            }
            isLoading = false
        }
    }
}

public func combineVerses(bibleVerses: [BibleVerse]) -> String {
    return bibleVerses.map { "\($0.verseId). \($0.text)" }.joined(separator: "\n")
}

// MARK: - Utilities
enum BibleError: Error {
    case invalidBook
    case invalidChapter
    case invalidTranslation
    case invalidReference
    case invalidURL
    case networkError
    case decodingError
}
