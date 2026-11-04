// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Orxooo
import XCTest
@testable import WakeMac

@MainActor final class ArtworkRotationTests: XCTestCase {
    func testAllThemesStartWithUniquePicturesAndRotateWithoutRepeatingASlot() {
        let rotation = ArtworkRotation()
        let slots = ConsoleArtworkModule.allCases
        for theme in [AppearanceController.Theme.dark, .light, .amber] {
            var previous = slots.map { rotation.artwork(for: $0, theme: theme) }
            XCTAssertEqual(Set(previous), Set(slots))
            for _ in 0..<100 {
                rotation.advance(theme: theme)
                let current = slots.map { rotation.artwork(for: $0, theme: theme) }
                XCTAssertEqual(Set(current), Set(slots))
                XCTAssertTrue(zip(previous, current).allSatisfy { $0 != $1 })
                previous = current
            }
        }
    }

    func testThemeRotationIsIndependentAndOneTickIsAppliedOnlyOnce() {
        let start = Date(timeIntervalSinceReferenceDate: 1000)
        let rotation = ArtworkRotation(now: start)
        let amber = rotation.orders["amber"]
        let dark = rotation.orders["dark"]
        XCTAssertFalse(rotation.advanceIfDue(theme: .light, now: start.addingTimeInterval(29)))
        XCTAssertTrue(rotation.advanceIfDue(theme: .light, now: start.addingTimeInterval(30)))
        let changed = rotation.orders["light"]
        XCTAssertFalse(rotation.advanceIfDue(theme: .light, now: start.addingTimeInterval(30)))
        XCTAssertEqual(rotation.orders["light"], changed)
        XCTAssertEqual(rotation.orders["amber"], amber)
        XCTAssertEqual(rotation.orders["dark"], dark)
        XCTAssertTrue(rotation.advanceIfDue(theme: .light, now: start.addingTimeInterval(60)))
        rotation.advance(theme: .dark)
        XCTAssertNotEqual(rotation.orders["dark"], dark)
        XCTAssertEqual(rotation.orders["amber"], amber)
    }

    func testArtworkFillsOriginalContainersAndKeepsOuterRimOutsideViewport() {
        for source in [CGSize(width: 1518, height: 1520), CGSize(width: 1466, height: 1466)] {
            for viewport in [CGSize(width: 220, height: 205), CGSize(width: 308, height: 250),
                             CGSize(width: 300, height: 280), CGSize(width: 266, height: 236),
                             CGSize(width: 420, height: 286), CGSize(width: 104, height: 104)] {
                let frame = ArtworkFraming.imageFrame(imageSize: source, viewport: viewport)
                let inner = frame.insetBy(dx: frame.width * ArtworkFraming.edgeInset,
                                          dy: frame.height * ArtworkFraming.edgeInset)
                XCTAssertLessThanOrEqual(inner.minX, 0.001)
                XCTAssertLessThanOrEqual(inner.minY, 0.001)
                XCTAssertGreaterThanOrEqual(inner.maxX, viewport.width - 0.001)
                XCTAssertGreaterThanOrEqual(inner.maxY, viewport.height - 0.001)
            }
        }
    }
}
