//
// SwiftBible
// File.swift
//
// Created on 2026-07-21
//
// Copyright ©2026 Thalia Myers.
//

import Foundation

struct BibleLookup: Codable, Sendable {
    let translations: [String: BibleTranslationInfo]
}

struct BibleTranslationInfo: Codable, Sendable {
    let id: Int
    let name: String
    let books: [String: BibleBookInfo]

    func bookId(named name: String) -> Int? {
        let normalized = name.trimmingCharacters(in: .whitespaces).lowercased()
        for (idString, book) in books where book.name.lowercased() == normalized {
            return Int(idString)
        }
        return nil
    }
}

struct BibleBookInfo: Codable, Sendable {
    let name: String
    let chapters: [String: BibleChapterInfo]
}

struct BibleChapterInfo: Codable, Sendable {
    let verseCount: Int
}

actor BibleLookupStore {
    static let shared = BibleLookupStore()

    private var cachedLookup: BibleLookup?
    private var inFlightTask: Task<BibleLookup, Error>?

    private init() {}

    func lookup() async throws -> BibleLookup {
        if let cachedLookup {
            return cachedLookup
        }

        if let inFlightTask {
            return try await inFlightTask.value
        }

        let task = Task<BibleLookup, Error> {
            guard let url = URL(string: "\(SwiftBible.apiBaseURL)/lookup.json") else {
                throw BibleError.invalidURL
            }
            let (data, _) = try await URLSession.shared.data(from: url)
            return try JSONDecoder().decode(BibleLookup.self, from: data)
        }
        inFlightTask = task

        do {
            let result = try await task.value
            cachedLookup = result
            inFlightTask = nil
            return result
        } catch {
            inFlightTask = nil
            throw error
        }
    }
}
