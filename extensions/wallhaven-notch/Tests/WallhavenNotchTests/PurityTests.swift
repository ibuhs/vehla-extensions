import Foundation
import Testing
@testable import WallhavenNotch

private func items(_ url: URL) -> [String: String] {
    Dictionary(uniqueKeysWithValues: (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value ?? "") })
}

@Suite struct TierTests {
    @Test func tiersAreCumulative() {
        #expect(PurityTier.regular.parameter == "100")     // just Regular
        #expect(PurityTier.sketchy.parameter == "110")     // Regular + Sketchy
        #expect(PurityTier.nsfw.parameter == "111")        // everything
    }

    @Test func titlesAreJustTheTierName() {
        #expect(PurityTier.allCases.map(\.title) == ["Regular", "Sketchy", "NSFW"])
    }

    @Test func withAnAPIKeyTheChosenTierIsSent() {
        for (tier, flag) in [(PurityTier.regular, "100"), (.sketchy, "110"), (.nsfw, "111")] {
            var q = WallhavenQuery()
            q.tier = tier
            #expect(items(WallhavenClient.searchURL(for: q, hasAPIKey: true))["purity"] == flag)
        }
    }

    @Test func withoutAnAPIKeyItIsAlwaysRegular() {
        for tier in PurityTier.allCases {
            var q = WallhavenQuery()
            q.tier = tier
            #expect(items(WallhavenClient.searchURL(for: q, hasAPIKey: false))["purity"] == "100", "\(tier)")
        }
    }

    @Test func theDefaultIsRegular() {
        #expect(WallhavenQuery().tier == .regular)
        #expect(items(WallhavenClient.searchURL(for: WallhavenQuery(), hasAPIKey: true))["purity"] == "100")
    }

    @Test func otherFiltersAreUnaffected() {
        var q = WallhavenQuery()
        q.text = "mountains"; q.minResolution = .uhd; q.sorting = .latest; q.tier = .sketchy
        let i = items(WallhavenClient.searchURL(for: q, hasAPIKey: true))
        #expect(i["q"] == "mountains" && i["atleast"] == "3840x2160" && i["sorting"] == "latest" && i["purity"] == "110")
        #expect(i["categories"] == "111" && i["page"] == "1")
    }

    @Test func settingsFromTheEarlierMultiSelectVersionMapToATier() {
        #expect(PurityTier(legacyMask: 1) == .regular)
        #expect(PurityTier(legacyMask: 3) == .sketchy)     // SFW + Sketchy
        #expect(PurityTier(legacyMask: 2) == .sketchy)
        #expect(PurityTier(legacyMask: 4) == .nsfw)
        #expect(PurityTier(legacyMask: 5) == .nsfw)
        #expect(PurityTier(legacyMask: 7) == .nsfw)
        #expect(PurityTier(legacyMask: 0) == .regular)
        #expect(PurityTier(rawValue: 9) == nil)            // junk in a hand-edited file is ignored
    }
}

private func wallpaper(_ id: String) throws -> Wallpaper {
    let json = #"""
    {"id":"\#(id)","url":"https://wallhaven.cc/w/\#(id)","path":"https://w.wallhaven.cc/full/ab/wallhaven-\#(id).jpg",
     "resolution":"3840x2160","file_size":1234567,"colors":["#112233"],"views":1,"favorites":2,
     "thumbs":{"large":"https://th.wallhaven.cc/lg/ab/\#(id).jpg","original":"https://th.wallhaven.cc/orig/ab/\#(id).jpg","small":"https://th.wallhaven.cc/small/ab/\#(id).jpg"}}
    """#
    return try JSONDecoder().decode(Wallpaper.self, from: Data(json.utf8))
}

@Suite struct SessionTests {
    @Test func roundTripsEverythingNeededToResume() throws {
        let state = SessionState(text: "forest", sorting: "random", page: 4, seed: "aB3dEf", selected: try wallpaper("x8y7z6"),
                                 showingFavorites: false, lastViewedID: "x8y7z6")
        let back = try JSONDecoder().decode(SessionState.self, from: JSONEncoder().encode(state))
        #expect(back == state)
        #expect(back.selected?.resolution == "3840x2160" && back.page == 4 && back.seed == "aB3dEf")
    }

    @Test func aSessionWithNothingSelectedRoundTrips() throws {
        let state = SessionState(text: "", sorting: "toplist", page: 1, seed: nil, selected: nil, showingFavorites: true, lastViewedID: nil)
        #expect(try JSONDecoder().decode(SessionState.self, from: JSONEncoder().encode(state)) == state)
    }

    @Test func aDamagedFileDoesNotDecode() {
        #expect((try? JSONDecoder().decode(SessionState.self, from: Data("{\"text\":1}".utf8))) == nil)
    }

    @Test func sortingNamesSurviveTheTrip() {
        for sorting in WallhavenSorting.allCases { #expect(WallhavenSorting(rawValue: sorting.rawValue) == sorting) }
    }
}

@Suite struct PreviewLayoutTests {
    private let screen = CGSize(width: 1400, height: 800)

    @Test func landscapeFitsWithinTheScreen() {
        let size = PreviewLayout.size(forResolution: "3840x2160", in: screen)
        #expect(size.width <= screen.width && size.height <= screen.height)
        #expect(abs(size.width / size.height - 16.0 / 9.0) < 0.01)
        #expect(size.height == 788 || size.width == 1400)        // as large as fits
    }

    @Test func portraitIsLimitedByHeight() {
        let size = PreviewLayout.size(forResolution: "2304x3072", in: screen)
        #expect(size.height == screen.height && size.width < size.height)
        #expect(abs(size.width / size.height - 0.75) < 0.01)
    }

    @Test func ultrawideKeepsItsShape() {
        let size = PreviewLayout.size(forResolution: "5120x1440", in: screen)
        #expect(size.width <= screen.width && abs(size.width / size.height - 5120.0 / 1440.0) < 0.02)
    }

    @Test func unreadableResolutionFallsBackToSixteenByNine() {
        for bad in ["", "wide", "0x0", "1920"] {
            let size = PreviewLayout.size(forResolution: bad, in: screen)
            #expect(abs(size.width / size.height - 16.0 / 9.0) < 0.02, "\(bad)")
        }
    }

    @Test func neverBiggerThanTheSpaceOrTinyOnASmallScreen() {
        let small = CGSize(width: 500, height: 300)
        let size = PreviewLayout.size(forResolution: "1920x1080", in: small)
        #expect(size.width <= small.width && size.height <= small.height)
        #expect(size.width > 100 && size.height > 100)
    }
}
