import Foundation
import SwiftUI

/// Lightweight SQL tokenizer for syntax highlighting. No external deps.
enum SQLSyntax {
    static func tokens(in source: String, palette: HighlightPalette) -> [Token] {
        var tokens: [Token] = []
        let characters = Array(source)
        var i = 0
        let n = characters.count

        while i < n {
            let c = characters[i]

            // line comment `-- ...`
            if c == "-" && i + 1 < n && characters[i + 1] == "-" {
                var j = i
                while j < n && characters[j] != "\n" { j += 1 }
                tokens.append(Token(.comment, String(characters[i..<j])))
                i = j
                continue
            }

            // string literal '...' or "..." (treat both as string)
            if c == "'" || c == "\"" {
                var j = i + 1
                while j < n {
                    if characters[j] == c {
                        if j + 1 < n && characters[j + 1] == c { j += 2; continue }
                        j += 1
                        break
                    }
                    j += 1
                }
                tokens.append(Token(.string, String(characters[i..<min(j, n)])))
                i = j
                continue
            }

            // number
            if c.isNumber || (c == "-" && i + 1 < n && characters[i + 1].isNumber) {
                var j = i
                while j < n && (characters[j].isNumber || characters[j] == "." || characters[j] == "e" || characters[j] == "E" || characters[j] == "-" || characters[j] == "+") {
                    j += 1
                }
                tokens.append(Token(.number, String(characters[i..<j])))
                i = j
                continue
            }

            // identifier / keyword
            if c.isLetter || c == "_" {
                var j = i
                while j < n && (characters[j].isLetter || characters[j].isNumber || characters[j] == "_") {
                    j += 1
                }
                let word = String(characters[i..<j])
                let kind: TokenKind = keywords.contains(word.uppercased()) ? .keyword : .identifier
                tokens.append(Token(kind, word))
                i = j
                continue
            }

            // symbols / whitespace / punctuation. Always consume at least one
            // character (start at i+1) so tokenizing can never stall — a lone
            // "-" is a break character and used to produce an empty chunk at
            // the same index, looping forever.
            var j = i + 1
            while j < n {
                let ch = characters[j]
                if ch.isLetter || ch.isNumber || ch == "_" || ch == "'" || ch == "\"" || ch == "-" {
                    break
                }
                j += 1
            }
            let chunk = String(characters[i..<j])
            if chunk.contains("(") || chunk.contains(")") || chunk.contains(",") {
                tokens.append(Token(.punctuation, chunk))
            } else {
                tokens.append(Token(.plain, chunk))
            }
            i = j
        }
        return tokens
    }

    struct Token {
        let kind: TokenKind
        let text: String
        init(_ kind: TokenKind, _ text: String) { self.kind = kind; self.text = text }
    }

    enum TokenKind {
        case keyword, string, number, comment, identifier, punctuation, plain
    }

    private static let keywords: Set<String> = [
        "SELECT", "FROM", "WHERE", "INSERT", "INTO", "VALUES", "UPDATE", "SET",
        "DELETE", "CREATE", "TABLE", "ALTER", "ADD", "DROP", "COLUMN", "INDEX",
        "VIEW", "PRIMARY", "KEY", "FOREIGN", "REFERENCES", "NOT", "NULL", "UNIQUE",
        "DEFAULT", "AUTOINCREMENT", "AND", "OR", "IN", "LIKE", "BETWEEN", "IS",
        "ORDER", "BY", "GROUP", "HAVING", "ASC", "DESC", "LIMIT", "OFFSET", "JOIN",
        "LEFT", "RIGHT", "INNER", "OUTER", "ON", "AS", "DISTINCT", "CASE", "WHEN",
        "THEN", "ELSE", "END", "COUNT", "SUM", "AVG", "MIN", "MAX", "CAST", "TEXT",
        "INTEGER", "REAL", "NUMERIC", "BLOB", "DATE", "DATETIME", "BOOLEAN", "JSON",
        "EXISTS", "UNION", "ALL", "WITH", "BEGIN", "COMMIT", "ROLLBACK", "TRANSACTION",
    ]
}

struct HighlightPalette {
    let keyword: Color
    let string: Color
    let number: Color
    let comment: Color
    let identifier: Color
    let punctuation: Color
    let plain: Color

    static func forScheme(_ dark: Bool) -> HighlightPalette {
        if dark {
            return HighlightPalette(
                keyword: Color(red: 0.53, green: 0.76, blue: 1.0),
                string: Color(red: 0.86, green: 0.66, blue: 0.53),
                number: Color(red: 0.72, green: 0.86, blue: 0.62),
                comment: Color(red: 0.5, green: 0.55, blue: 0.6),
                identifier: Color(red: 0.86, green: 0.88, blue: 0.9),
                punctuation: Color(red: 0.65, green: 0.67, blue: 0.72),
                plain: Color(red: 0.9, green: 0.92, blue: 0.95)
            )
        } else {
            return HighlightPalette(
                keyword: Color(red: 0.05, green: 0.35, blue: 0.72),
                string: Color(red: 0.72, green: 0.24, blue: 0.05),
                number: Color(red: 0.15, green: 0.45, blue: 0.35),
                comment: Color(red: 0.42, green: 0.46, blue: 0.5),
                identifier: Color(red: 0.1, green: 0.1, blue: 0.1),
                punctuation: Color(red: 0.3, green: 0.3, blue: 0.34),
                plain: Color(red: 0.15, green: 0.15, blue: 0.17)
            )
        }
    }
}

/// Renders attributed SQL text for a SwiftUI `Text`.
struct SQLAttributed {
    let source: String
    let dark: Bool

    init(_ source: String, dark: Bool) {
        self.source = source
        self.dark = dark
    }

    var attributed: AttributedString {
        var result = AttributedString()
        let palette = HighlightPalette.forScheme(dark)
        for token in SQLSyntax.tokens(in: source, palette: palette) {
            var piece = AttributedString(token.text)
            var d = AttributeContainer()
            switch token.kind {
            case .keyword: d.foregroundColor = palette.keyword
            case .string: d.foregroundColor = palette.string
            case .number: d.foregroundColor = palette.number
            case .comment: d.foregroundColor = palette.comment
            case .identifier: d.foregroundColor = palette.identifier
            case .punctuation: d.foregroundColor = palette.punctuation
            case .plain: d.foregroundColor = palette.plain
            }
            piece.mergeAttributes(d)
            result.append(piece)
        }
        return result
    }
}