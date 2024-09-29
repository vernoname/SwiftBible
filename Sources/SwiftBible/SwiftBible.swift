import SwiftUI

// MARK: - Main SwiftBible struct
public struct SwiftBible {
    public static func fetchVerses(reference: String) async throws -> [BibleVerse] {
        let (book, chapter, verse) = parseReference(reference)
        return try await fetchVerses(book: book, chapter: chapter, verse: verse)
    }
    
    public static func fetchVerses(book: String, chapter: String, verse: String) async throws -> [BibleVerse] {
        guard let bookId = booksOfTheBible[book] else {
            throw BibleError.invalidBook
        }
        
        let verses = try await fetchVerses(version: "NIV", bookId: bookId, chapter: chapter)
        return filterVerses(verses: verses, verseRange: verse)
    }
    
    private static func parseReference(_ reference: String) -> (book: String, chapter: String, verse: String) {
        let components = reference.components(separatedBy: .whitespaces)
        var book = components.prefix(while: { !$0.contains(":") }).joined(separator: " ")
        var chapter = ""
        var verse = ""
        
        if let lastComponent = components.last, lastComponent.contains(":") {
            let parts = lastComponent.split(separator: ":")
            chapter = String(parts[0])
            verse = parts.count > 1 ? String(parts[1]) : ""
        } else if components.count > 1 {
            chapter = components.last ?? ""
        }
        
        if let lastSpace = book.lastIndex(of: " "), Int(book.suffix(from: book.index(after: lastSpace))) != nil {
            chapter = String(book.suffix(from: book.index(after: lastSpace)))
            book = String(book[..<lastSpace])
        }
        
        return (book, chapter, verse)
    }
    
    private static func fetchVerses(version: String, bookId: Int, chapter: String) async throws -> [VerseResponse] {
        let urlString = "https://bible-go-api.rkeplin.com/v1/books/\(bookId)/chapters/\(chapter)?translation=\(version)"
        guard let url = URL(string: urlString) else {
            throw BibleError.invalidURL
        }
        
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode([VerseResponse].self, from: data)
    }
    
    private static func filterVerses(verses: [VerseResponse], verseRange: String) -> [BibleVerse] {
        if verseRange.isEmpty {
            return verses.map { BibleVerse(id: $0.id, bookId: $0.book.id, chapterId: $0.chapterId, verseId: $0.verseId, text: $0.verse) }
        }
        
        let range = verseRange.components(separatedBy: "-").compactMap { Int($0) }
        
        if range.count == 2 {
            return verses.filter { $0.verseId >= range[0] && $0.verseId <= range[1] }
                .map { BibleVerse(id: $0.id, bookId: $0.book.id, chapterId: $0.chapterId, verseId: $0.verseId, text: $0.verse) }
        } else if range.count == 1 {
            return verses.filter { $0.verseId == range[0] }
                .map { BibleVerse(id: $0.id, bookId: $0.book.id, chapterId: $0.chapterId, verseId: $0.verseId, text: $0.verse) }
        } else {
            return verses.map { BibleVerse(id: $0.id, bookId: $0.book.id, chapterId: $0.chapterId, verseId: $0.verseId, text: $0.verse) }
        }
    }
}

// MARK: - Models
public struct BibleVerse: Identifiable, Codable {
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

struct BibleVersion: Hashable {
    let name: String
    let id: String
}

struct VerseResponse: Codable {
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
public struct BibleVersePickerView: View {
    @Binding var selectedVerses: [BibleVerse]
    @State private var isPresented = false
    
    public init(selectedVerses: Binding<[BibleVerse]>) {
        self._selectedVerses = selectedVerses
    }
    
    public var body: some View {
        Button("Select Bible Verse") {
            isPresented = true
        }
        .sheet(isPresented: $isPresented) {
            BibleVersePicker(selectedVerses: $selectedVerses)
        }
    }
}

struct BibleVersePicker: View {
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
                        ForEach(bibleVersions, id: \.id) { version in
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
            .listStyle(InsetGroupedListStyle())
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
    }
    
    private func parseVerseReference() {
        let components = verseReference.components(separatedBy: .whitespaces)
        book = components.prefix(while: { !$0.contains(":") }).joined(separator: " ")
        
        if let lastComponent = components.last, lastComponent.contains(":") {
            let parts = lastComponent.split(separator: ":")
            chapter = String(parts[0])
            verse = parts.count > 1 ? String(parts[1]) : ""
        } else if components.count > 1 {
            chapter = components.last ?? ""
            verse = ""
        }
        
        if let lastSpace = book.lastIndex(of: " "), Int(book.suffix(from: book.index(after: lastSpace))) != nil {
            chapter = String(book.suffix(from: book.index(after: lastSpace)))
            book = String(book[..<lastSpace])
        }
        
        fetchVerses()
    }
    
    private func fetchVerses() {
        isLoading = true
        Task {
            do {
                verseContent = try await SwiftBible.fetchVerses(book: book, chapter: chapter, verse: verse)
            } catch {
                print("Error fetching verses: \(error)")
            }
            isLoading = false
        }
    }
}

// MARK: - Utilities
enum BibleError: Error {
    case invalidBook
    case invalidURL
    case networkError
    case decodingError
}

// MARK: - Constants
let bibleVersions = [
    BibleVersion(name: "New International Version", id: "NIV"),
    BibleVersion(name: "King James Version", id: "KJV"),
    BibleVersion(name: "New Living Translation", id: "NLT"),
    BibleVersion(name: "American Standard Version", id: "ASV"),
    BibleVersion(name: "English Standard Version", id: "ESV"),
]


let booksOfTheBible: [String: Int] = [
    "Genesis": 1,
    "Exodus": 2,
    "Leviticus": 3,
    "Numbers": 4,
    "Deuteronomy": 5,
    "Joshua": 6,
    "Judges": 7,
    "Ruth": 8,
    "1 Samuel": 9,
    "2 Samuel": 10,
    "1 Kings": 11,
    "2 Kings": 12,
    "1 Chronicles": 13,
    "2 Chronicles": 14,
    "Ezra": 15,
    "Nehemiah": 16,
    "Esther": 17,
    "Job": 18,
    "Psalm": 19,
    "Proverbs": 20,
    "Ecclesiastes": 21,
    "Song of Solomon": 22,
    "Isaiah": 23,
    "Jeremiah": 24,
    "Lamentations": 25,
    "Ezekiel": 26,
    "Daniel": 27,
    "Hosea": 28,
    "Joel": 29,
    "Amos": 30,
    "Obadiah": 31,
    "Jonah": 32,
    "Micah": 33,
    "Nahum": 34,
    "Habakkuk": 35,
    "Zephaniah": 36,
    "Haggai": 37,
    "Zechariah": 38,
    "Malachi": 39,
    "Matthew": 40,
    "Mark": 41,
    "Luke": 42,
    "John": 43,
    "Acts": 44,
    "Romans": 45,
    "1 Corinthians": 46,
    "2 Corinthians": 47,
    "Galatians": 48,
    "Ephesians": 49,
    "Philippians": 50,
    "Colossians": 51,
    "1 Thessalonians": 52,
    "2 Thessalonians": 53,
    "1 Timothy": 54,
    "2 Timothy": 55,
    "Titus": 56,
    "Philemon": 57,
    "Hebrews": 58,
    "James": 59,
    "1 Peter": 60,
    "2 Peter": 61,
    "1 John": 62,
    "2 John": 63,
    "3 John": 64,
    "Jude": 65,
    "Revelation": 66
]
