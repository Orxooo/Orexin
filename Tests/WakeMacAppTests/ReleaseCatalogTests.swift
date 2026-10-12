// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Orxooo
import XCTest
@testable import WakeMac

final class ReleaseCatalogTests: XCTestCase {
    private func release(_ tag: String, preview: Bool = false, draft: Bool = false,
                         repository: String = "Orxooo/Orexin") -> GitHubRelease {
        GitHubRelease(tagName: tag, htmlURL: "https://github.com/\(repository)/releases/tag/\(tag)",
                      draft: draft, prerelease: preview)
    }

    func testPreviewInstallationFindsFirstPreviewRelease() throws {
        let releases = [release("v0.1.0-preview", preview: true)]
        XCTAssertEqual(ReleaseCatalog.latest(in: releases, includePreviews: true)?.tagName, "v0.1.0-preview")
        XCTAssertEqual(ReleaseCatalog.apiURL.path, "/repos/Orxooo/Orexin/releases")
    }

    func testDraftsAndOtherRepositoryLinksAreNotOffered() {
        let releases = [release("v9.0.0", draft: true), release("v8.0.0", repository: "other/repo"), release("v0.1.0")]
        XCTAssertEqual(ReleaseCatalog.latest(in: releases, includePreviews: true)?.tagName, "v0.1.0")
    }

    func testVersionOrderHandlesStableAndNumberedPreviews() throws {
        let tags = ["v0.1.0-preview.2", "v0.1.0-preview.10", "V0.1.0", "v0.2.0-preview"]
        let versions = try tags.map { try XCTUnwrap(ReleaseVersion($0)) }
        for (older, newer) in zip(versions, versions.dropFirst()) { XCTAssertLessThan(older, newer) }
        XCTAssertNil(ReleaseVersion("not-a-version"))
        XCTAssertNil(ReleaseVersion(""))
        XCTAssertNil(ReleaseVersion("v"))
        XCTAssertNil(ReleaseVersion("0.1.0-"))
    }

    func testStableInstallDoesNotOfferPreviewAndListOrderDoesNotMatter() {
        let releases = [release("v0.1.0"), release("v0.3.0-preview", preview: true), release("v0.2.0"), release("v0.2.1-preview")]
        XCTAssertEqual(ReleaseCatalog.latest(in: releases, includePreviews: false)?.tagName, "v0.2.0")
        XCTAssertEqual(ReleaseCatalog.latest(in: releases, includePreviews: true)?.tagName, "v0.3.0-preview")
    }

    func testPublicGitHubListResponseDecodesPreview() throws {
        let data = Data(#"[{"tag_name":"v0.1.0-preview","html_url":"https://github.com/Orxooo/Orexin/releases/tag/v0.1.0-preview","draft":false,"prerelease":true}]"#.utf8)
        let releases = try JSONDecoder().decode([GitHubRelease].self, from: data)
        XCTAssertEqual(ReleaseCatalog.latest(in: releases, includePreviews: true)?.tagName, "v0.1.0-preview")
    }
}
