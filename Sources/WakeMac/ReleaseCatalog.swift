// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Orxooo
import Foundation

enum OrexinRelease {
    static let repositoryURL = URL(string: "https://github.com/Orxooo/Orexin")!
    static let releasesURL = repositoryURL.appendingPathComponent("releases")
    static let issuesURL = repositoryURL.appendingPathComponent("issues/new")
    static var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.3.0" }
    static var channel: String { Bundle.main.object(forInfoDictionaryKey: "OrexinReleaseChannel") as? String ?? "Preview" }
    static var displayVersion: String { "V\(version)" + (channel.isEmpty ? "" : " \(channel)") }
    static var versionTag: String { "v\(version)" + (channel.isEmpty ? "" : "-\(channel.lowercased())") }
}

struct GitHubRelease: Decodable {
    let tagName: String
    let htmlURL: String
    let draft: Bool
    let prerelease: Bool
    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name", htmlURL = "html_url", draft, prerelease
    }
    var version: ReleaseVersion? { ReleaseVersion(tagName) }
    var url: URL? {
        guard let url = URL(string: htmlURL), url.scheme == "https", url.host == "github.com",
              url.path.hasPrefix("/Orxooo/Orexin/releases/tag/") else { return nil }
        return url
    }
}

enum ReleaseCatalog {
    static let apiURL = URL(string: "https://api.github.com/repos/Orxooo/Orexin/releases?per_page=100")!
    static func latest(in releases: [GitHubRelease], includePreviews: Bool) -> GitHubRelease? {
        releases.filter { !$0.draft && $0.version != nil && $0.url != nil &&
            (includePreviews || (!$0.prerelease && !$0.version!.isPrerelease)) }
            .max { $0.version! < $1.version! }
    }
}

/// Version ordering includes prerelease identifiers so 0.1.0 succeeds 0.1.0-preview.
struct ReleaseVersion: Comparable {
    private let numbers: [Int]
    private let prerelease: [String]
    var isPrerelease: Bool { !prerelease.isEmpty }

    init?(_ tag: String) {
        let value = tag.first == "v" || tag.first == "V" ? String(tag.dropFirst()) : tag
        guard let version = value.split(separator: "+", maxSplits: 1, omittingEmptySubsequences: false).first,
              !version.isEmpty else { return nil }
        let parts = version.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        let numbers = parts[0].split(separator: ".", omittingEmptySubsequences: false)
        guard numbers.count == 3, numbers.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }),
              numbers.compactMap({ Int($0) }).count == 3 else { return nil }
        self.numbers = numbers.compactMap { Int($0) }
        prerelease = parts.count == 2 ? parts[1].split(separator: ".", omittingEmptySubsequences: false).map(String.init) : []
        guard prerelease.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") } }) else { return nil }
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.numbers != rhs.numbers { return lhs.numbers.lexicographicallyPrecedes(rhs.numbers) }
        if lhs.prerelease.isEmpty || rhs.prerelease.isEmpty { return !lhs.prerelease.isEmpty && rhs.prerelease.isEmpty }
        for (a, b) in zip(lhs.prerelease, rhs.prerelease) where a != b {
            switch (Int(a), Int(b)) {
            case let (x?, y?): return x < y
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return a < b
            }
        }
        return lhs.prerelease.count < rhs.prerelease.count
    }
}
