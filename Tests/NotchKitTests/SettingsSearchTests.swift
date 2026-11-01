import Testing
@testable import NotchKit

@Suite("Settings search")
struct SettingsSearchTests {
    @Test func matchesFeaturesAndSynonyms() {
        #expect(SettingsSearch.results(for: "LYRICS").contains { $0.page == .media && $0.title == "Lyrics" })
        #expect(SettingsSearch.results(for: "claude quota").contains { $0.page == .coding })
        #expect(SettingsSearch.results(for: "software update").contains { $0.page == .update })
    }

    @Test func handlesNoResultsAndEmptySearch() {
        #expect(SettingsSearch.results(for: "  ").isEmpty)
        #expect(SettingsSearch.results(for: "not-a-real-setting").isEmpty)
    }
}

@MainActor
@Suite("Settings navigation")
struct SettingsNavigationTests {
    @Test func backAndForwardFollowVisitedPages() {
        let navigation = SettingsNavigation()
        navigation.navigateTo(selection: .general, generalPage: .about)
        navigation.navigateTo(selection: .appearance, generalPage: .overview)
        navigation.goBack()
        #expect(navigation.current == .init(selection: .general, generalPage: .about))
        navigation.goBack()
        #expect(navigation.current == .init(selection: .general, generalPage: .overview))
        navigation.goForward()
        #expect(navigation.current == .init(selection: .general, generalPage: .about))
        navigation.navigateTo(selection: .home, generalPage: .overview)
        #expect(!navigation.canGoForward)
    }
}
