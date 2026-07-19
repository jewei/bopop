#!/usr/bin/env swift
//
// generate-emoji.swift
//
// Generates `Sources/BopopKit/Resources/emoji.json` by joining Unicode's
// emoji-test.txt (canonical fully-qualified emoji + display ordering) with
// CLDR's English annotations (human-readable name + search keywords).
//
// Usage:
//   swift Support/generate-emoji.swift [emoji-test.txt] [annotations.json] \
//       > Sources/BopopKit/Resources/emoji.json
//
// Both arguments are optional paths to already-downloaded copies of the two
// source files below. Pass them to run entirely offline (recommended — the
// upstream files change over time, so a pinned local copy is reproducible).
// When an argument is omitted, the script fetches the corresponding source
// over the network via `curl` (3 attempts, 60 s timeout each).
//
// Sources:
//   - https://unicode.org/Public/emoji/latest/emoji-test.txt
//   - https://raw.githubusercontent.com/unicode-org/cldr-json/main/cldr-json/cldr-annotations-full/annotations/en/annotations.json
//
// Join logic:
//   - Only "; fully-qualified" lines are kept (skips "component",
//     "minimally-qualified", and "unqualified" lines).
//   - Lines whose codepoint sequence includes a skin-tone modifier
//     (U+1F3FB–U+1F3FF) are dropped — the catalog carries base emoji only.
//   - The emoji character itself is rebuilt from the line's hex codepoints
//     (not scraped from the trailing comment) so the exact fully-qualified
//     scalar sequence is used as the join key and as `char` in the output.
//   - CLDR annotations are looked up by that exact character; if absent, a
//     second lookup strips U+FE0F (variation selector-16) from both sides,
//     since CLDR sometimes omits VS16 where emoji-test.txt includes it
//     (e.g. "☺️" in emoji-test.txt vs. "☺" as the CLDR key).
//   - `name` = CLDR `tts` (text-to-speech name) when found, else falls back
//     to the emoji-test.txt trailing description (e.g. "grinning face").
//   - `keywords` = CLDR `default` annotation list when found, else empty.
//
// Output is a compact JSON array of `{char, name, keywords}` objects in
// emoji-test.txt's canonical (CLDR group) order — this order becomes each
// entry's catalog index, which `EmojiProvider` uses as `sortHint`.
//
// Sanity checks (run automatically, non-zero exit on failure):
//   - total entry count > 1500
//   - 🔥 is present with name "fire" and keyword "flame"

import Foundation

// MARK: - CLI arguments

let arguments = CommandLine.arguments
let emojiTestPath = arguments.count > 1 ? arguments[1] : nil
let annotationsPath = arguments.count > 2 ? arguments[2] : nil

func fail(_ message: String) -> Never {
    FileHandle.standardError.write("generate-emoji: \(message)\n".data(using: .utf8)!)
    exit(1)
}

// MARK: - Fetching

func fetchViaCurl(_ urlString: String, attempts: Int = 3) -> String {
    var lastStatus: Int32 = -1
    for attempt in 1...attempts {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        process.arguments = ["-sS", "--max-time", "60", urlString]
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
        } catch {
            fail("failed to launch curl for \(urlString): \(error)")
        }

        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        lastStatus = process.terminationStatus
        if lastStatus == 0, let text = String(data: data, encoding: .utf8), !text.isEmpty {
            return text
        }
        FileHandle.standardError.write(
            "generate-emoji: curl attempt \(attempt)/\(attempts) failed (status \(lastStatus)) for \(urlString)\n"
                .data(using: .utf8)!
        )
    }
    fail("could not fetch \(urlString) after \(attempts) attempts (last status \(lastStatus))")
}

func loadSource(localPath: String?, remoteURL: String, label: String) -> String {
    if let localPath {
        guard let contents = try? String(contentsOfFile: localPath, encoding: .utf8) else {
            fail("could not read local \(label) file at \(localPath)")
        }
        return contents
    }
    return fetchViaCurl(remoteURL)
}

let emojiTestText = loadSource(
    localPath: emojiTestPath,
    remoteURL: "https://unicode.org/Public/emoji/latest/emoji-test.txt",
    label: "emoji-test.txt"
)
let annotationsText = loadSource(
    localPath: annotationsPath,
    remoteURL: "https://raw.githubusercontent.com/unicode-org/cldr-json/main/cldr-json/cldr-annotations-full/annotations/en/annotations.json",
    label: "annotations.json"
)

// MARK: - CLDR annotations

struct AnnotationsFile: Decodable {
    struct Inner: Decodable {
        let annotations: [String: Annotation]
    }
    struct Annotation: Decodable {
        let defaultKeywords: [String]?
        let tts: [String]?
        enum CodingKeys: String, CodingKey {
            case defaultKeywords = "default"
            case tts
        }
    }
    let annotations: Inner
}

guard let annotationsData = annotationsText.data(using: .utf8),
      let annotationsFile = try? JSONDecoder().decode(AnnotationsFile.self, from: annotationsData)
else {
    fail("could not decode annotations.json")
}

let rawAnnotations = annotationsFile.annotations.annotations

let variationSelector16: Character = "\u{FE0F}"
func strippingVariationSelector(_ string: String) -> String {
    String(string.filter { $0 != variationSelector16 })
}

var strippedAnnotationIndex: [String: String] = [:]
for key in rawAnnotations.keys {
    let stripped = strippingVariationSelector(key)
    if strippedAnnotationIndex[stripped] == nil {
        strippedAnnotationIndex[stripped] = key
    }
}

func annotation(for char: String) -> AnnotationsFile.Annotation? {
    if let exact = rawAnnotations[char] {
        return exact
    }
    let stripped = strippingVariationSelector(char)
    if let byStripped = rawAnnotations[stripped] {
        return byStripped
    }
    if let key = strippedAnnotationIndex[stripped] {
        return rawAnnotations[key]
    }
    return nil
}

// MARK: - emoji-test.txt

struct Entry: Encodable {
    let char: String
    let name: String
    let keywords: [String]
}

let skinToneModifiers: Set<String> = ["1F3FB", "1F3FC", "1F3FD", "1F3FE", "1F3FF"]

func charFromHexCodepoints(_ tokens: [String]) -> String? {
    var scalars = String.UnicodeScalarView()
    for token in tokens {
        guard let value = UInt32(token, radix: 16), let scalar = Unicode.Scalar(value) else {
            return nil
        }
        scalars.append(scalar)
    }
    return String(scalars)
}

func fallbackName(fromComment comment: String) -> String {
    // comment looks like "😀 E1.0 grinning face": drop the glyph token and
    // the "E<version>" token, keep the remaining words as the name.
    let words = comment.split(separator: " ", omittingEmptySubsequences: true)
    guard words.count > 2 else {
        return comment.trimmingCharacters(in: .whitespaces)
    }
    return words.dropFirst(2).joined(separator: " ")
}

func dedupedKeywords(_ keywords: [String]) -> [String] {
    var seen = Set<String>()
    var result: [String] = []
    for keyword in keywords {
        if seen.insert(keyword).inserted {
            result.append(keyword)
        }
    }
    return result
}

var entries: [Entry] = []
entries.reserveCapacity(2000)

for line in emojiTestText.split(separator: "\n", omittingEmptySubsequences: true) {
    guard line.contains("; fully-qualified") else {
        continue
    }

    let fields = line.components(separatedBy: ";")
    guard fields.count >= 2 else {
        continue
    }

    let hexTokens = fields[0]
        .trimmingCharacters(in: .whitespaces)
        .split(separator: " ")
        .map(String.init)
    guard !hexTokens.isEmpty else {
        continue
    }
    if hexTokens.contains(where: { skinToneModifiers.contains($0) }) {
        continue
    }
    guard let char = charFromHexCodepoints(hexTokens) else {
        continue
    }

    let rest = fields[1]
    guard let hashRange = rest.range(of: "#") else {
        continue
    }
    let comment = rest[hashRange.upperBound...].trimmingCharacters(in: .whitespaces)
    let fallback = fallbackName(fromComment: comment)

    if let annotation = annotation(for: char) {
        let name = annotation.tts?.first?.trimmingCharacters(in: .whitespaces).isEmpty == false
            ? annotation.tts!.first!
            : fallback
        let keywords = dedupedKeywords(annotation.defaultKeywords ?? [])
        entries.append(Entry(char: char, name: name, keywords: keywords))
    } else {
        entries.append(Entry(char: char, name: fallback, keywords: []))
    }
}

// MARK: - Sanity checks

guard entries.count > 1500 else {
    fail("only \(entries.count) entries generated; expected > 1500")
}

guard let fire = entries.first(where: { $0.char == "\u{1F525}" }) else {
    fail("🔥 (U+1F525) missing from generated entries")
}
guard fire.name == "fire" else {
    fail("🔥 name is \"\(fire.name)\", expected \"fire\"")
}
guard fire.keywords.contains("flame") else {
    fail("🔥 keywords \(fire.keywords) do not contain \"flame\"")
}

// MARK: - Output

let encoder = JSONEncoder()
encoder.outputFormatting = [.sortedKeys]
guard let data = try? encoder.encode(entries), let json = String(data: data, encoding: .utf8) else {
    fail("failed to encode entries as JSON")
}

print(json)

FileHandle.standardError.write(
    "generate-emoji: wrote \(entries.count) entries (🔥 -> name=\"\(fire.name)\", keywords contains \"flame\")\n"
        .data(using: .utf8)!
)
