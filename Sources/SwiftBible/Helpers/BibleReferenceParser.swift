//
// SwiftBible
// File.swift
//
// Created on 2026-07-21
//
// Copyright ©2026 Thalia Myers.
//

import Foundation

// A parsed verse reference, e.g. "Matthew 1:10-2:5" or "Romans 8:28-30" or "John 3:16" or "Genesis 1".
struct ParsedBibleReference: Sendable {
    let book: String
    let startChapter: Int
    let startVerse: Int?
    let endChapter: Int
    let endVerse: Int?

    static func parse(_ reference: String) -> ParsedBibleReference? {
        let trimmed = reference.trimmingCharacters(in: .whitespaces)
        let components = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        guard !components.isEmpty else { return nil }

        let book: String
        let spec: String

        if let last = components.last, last.rangeOfCharacter(from: .decimalDigits) != nil {
            book = components.dropLast().joined(separator: " ")
            spec = last
        } else {
            book = trimmed
            spec = ""
        }

        guard !book.isEmpty, !spec.isEmpty else { return nil }

        let dashParts = spec.split(separator: "-", maxSplits: 1)
        let startPart = String(dashParts[0])
        let endPart = dashParts.count > 1 ? String(dashParts[1]) : nil

        let startColonParts = startPart.split(separator: ":")
        guard let startChapter = Int(startColonParts[0]) else { return nil }
        let startVerse = startColonParts.count > 1 ? Int(startColonParts[1]) : nil

        var endChapter = startChapter
        var endVerse: Int?

        if let endPart {
            if endPart.contains(":") {
                let endColonParts = endPart.split(separator: ":")
                guard let parsedEndChapter = Int(endColonParts[0]) else { return nil }
                endChapter = parsedEndChapter
                endVerse = endColonParts.count > 1 ? Int(endColonParts[1]) : nil
            } else {
                endVerse = Int(endPart)
            }
        } else {
            endVerse = startVerse
        }

        return ParsedBibleReference(book: book, startChapter: startChapter, startVerse: startVerse, endChapter: endChapter, endVerse: endVerse)
    }
}
