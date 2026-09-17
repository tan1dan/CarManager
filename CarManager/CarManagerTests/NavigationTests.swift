import Testing
import Foundation
@testable import CarManager

@Suite("Main navigation")
@MainActor
struct MainNavigationTests {

    @Test("The tab set matches the designed primary sections")
    func tabSet() {
        #expect(AppTab.allCases == [.home, .garage, .ai, .profile])
    }

    @Test("Selecting a tab switches the router")
    func selectTab() {
        let router = makeRouter(context: .make())
        #expect(router.selectedTab == .home)
        router.select(tab: .garage)
        #expect(router.selectedTab == .garage)
    }

    @Test("Each tab owns an independent navigation stack")
    func independentStacks() {
        let router = makeRouter(context: .make())
        let vehicleID = VehicleID()
        router.router(for: .garage).push(.vehicleDetail(vehicleID))

        #expect(router.router(for: .garage).path.count == 1)
        #expect(router.router(for: .home).path.isEmpty)
    }

    @Test("Pushing then popping returns to the previous screen")
    func backNavigation() {
        let router = makeRouter(context: .make())
        let vehicleID = VehicleID()
        router.push(.vehicleDetail(vehicleID), in: .garage)
        router.push(.fuelHistory(vehicleID), in: .garage)
        #expect(router.router(for: .garage).path.count == 2)

        router.router(for: .garage).pop()
        #expect(router.router(for: .garage).path == [.vehicleDetail(vehicleID)])

        router.router(for: .garage).popToRoot()
        #expect(router.router(for: .garage).path.isEmpty)
    }

    @Test("Modals stack, so a paywall can cover an editor")
    func modalStacking() {
        let router = makeRouter(context: .make())
        router.present(.vehicleEditor(.create))
        router.present(.paywall(.vehicleLimit))

        #expect(router.modalStack.count == 2)
        #expect(router.activeModal == .paywall(.vehicleLimit))

        router.dismissModal()
        #expect(router.activeModal == .vehicleEditor(.create))
    }

    @Test("Quick log replaces itself with the next sheet instead of stacking")
    func quickLogReplacement() {
        let router = makeRouter(context: .make())
        router.present(.quickLog)
        router.replaceModal(with: .fuelEditor(.create(VehicleID())))

        #expect(router.modalStack.count == 1)
        if case .fuelEditor = router.activeModal {} else {
            Issue.record("Expected the fuel editor to replace the quick-log sheet")
        }
    }

    @Test("Full-screen flows are separate from the navigation stacks")
    func fullScreenIsolation() {
        let router = makeRouter(context: .make())
        router.presentFullScreen(.camera(.vehiclePhoto))

        #expect(router.fullScreen == .camera(.vehiclePhoto))
        #expect(router.router(for: .home).path.isEmpty)

        router.dismissFullScreen()
        #expect(router.fullScreen == nil)
    }

    @Test("Every AppDestination survives a Codable round trip (deep links, state restoration)")
    func destinationRoundTrip() throws {
        let destinations: [AppDestination] = [
            .tab(.garage, path: [.vehicleDetail(VehicleID()), .fuelHistory(VehicleID())]),
            .modal(.paywall(.feature(.receiptScan))),
            .fullScreen(.camera(.dashboard)),
            AppDestination(tab: .profile, path: [.settings, .settingsSection(.units)])
        ]
        for destination in destinations {
            let data = try JSONEncoder().encode(destination)
            #expect(try JSONDecoder().decode(AppDestination.self, from: data) == destination)
        }
    }
}

@Suite("Deep links")
struct DeepLinkTests {

    @Test("A vehicle link targets the garage stack")
    func vehicleLink() throws {
        let id = VehicleID()
        let url = URL(string: "carmanager://vehicle/\(id.raw.uuidString)")!
        let destination = try #require(DeepLinkParser.destination(from: url))

        #expect(destination.tab == .garage)
        #expect(destination.path == [.vehicleDetail(id)])
    }

    @Test("A nested vehicle link targets the right sub-screen")
    func vehicleFuelLink() throws {
        let id = VehicleID()
        let url = URL(string: "carmanager://vehicle/\(id.raw.uuidString)/fuel")!
        let destination = try #require(DeepLinkParser.destination(from: url))

        #expect(destination.path == [.vehicleDetail(id), .fuelHistory(id)])
    }

    @Test("An add-fuel link opens the editor as a sheet")
    func addFuelLink() throws {
        let id = VehicleID()
        let url = URL(string: "carmanager://vehicle/\(id.raw.uuidString)/fuel/add")!
        let destination = try #require(DeepLinkParser.destination(from: url))

        #expect(destination.modal == .fuelEditor(.create(id)))
    }

    @Test("An AI chat link carries the conversation id")
    func aiChatLink() throws {
        let id = ConversationID()
        let url = URL(string: "carmanager://ai/chat?conversation=\(id.raw.uuidString)")!
        let destination = try #require(DeepLinkParser.destination(from: url))

        #expect(destination.tab == .ai)
        #expect(destination.path == [.aiChat(id)])
    }

    @Test("A settings link targets the section")
    func settingsLink() throws {
        let url = URL(string: "carmanager://settings/units")!
        let destination = try #require(DeepLinkParser.destination(from: url))

        #expect(destination.tab == .profile)
        #expect(destination.path == [.settings, .settingsSection(.units)])
    }

    @Test("A premium link opens the paywall")
    func premiumLink() throws {
        let destination = try #require(
            DeepLinkParser.destination(from: URL(string: "carmanager://premium")!)
        )
        #expect(destination.modal == .paywall(.settingsUpgrade))
    }

    @Test("Unknown and malformed links return nil rather than crashing")
    func unknownLinks() {
        #expect(DeepLinkParser.destination(from: URL(string: "carmanager://nonsense")!) == nil)
        #expect(DeepLinkParser.destination(from: URL(string: "https://example.com")!) == nil)
        #expect(DeepLinkParser.destination(from: URL(string: "carmanager://vehicle/not-a-uuid")!) == nil)
    }

    @Test("A notification payload takes the same path as a URL deep link")
    func notificationPayload() throws {
        let expected = AppDestination.tab(.home, path: [.alerts])
        let payload: [AnyHashable: Any] = ["destination": try JSONEncoder().encode(expected)]

        #expect(DeepLinkParser.destination(fromNotificationPayload: payload) == expected)
    }
}

@Suite("Modal stack")
@MainActor
struct ModalStackTests {

    @Test("Modals are addressable by depth so a paywall can genuinely cover an editor")
    func depthAddressing() {
        let router = makeRouter(context: .make())
        router.present(.vehicleEditor(.create))
        router.present(.paywall(.vehicleLimit))

        #expect(router.modal(at: 0) == .vehicleEditor(.create))
        #expect(router.modal(at: 1) == .paywall(.vehicleLimit))
        #expect(router.modal(at: 2) == nil)
    }

    @Test("Dismissing a depth also dismisses everything stacked above it")
    func dismissFromDepth() {
        let router = makeRouter(context: .make())
        router.present(.vehicleEditor(.create))
        router.present(.paywall(.vehicleLimit))
        router.present(.legal(.termsOfUse))

        router.dismissModal(from: 1)
        #expect(router.modalStack == [.vehicleEditor(.create)])

        router.dismissModal(from: 0)
        #expect(router.modalStack.isEmpty)
    }

    @Test("Dismissing a depth that is not presented is a no-op")
    func dismissOutOfRange() {
        let router = makeRouter(context: .make())
        router.present(.quickLog)
        router.dismissModal(from: 5)

        #expect(router.modalStack == [.quickLog])
    }

    @Test("Purchasing from a stacked paywall leaves the editor underneath presented")
    func paywallOverEditorLeavesEditor() {
        let router = makeRouter(context: .make())
        router.present(.vehicleEditor(.create))
        router.present(.paywall(.vehicleLimit))

        // What PaywallViewModel does on a successful purchase.
        router.dismissModal()

        #expect(router.activeModal == .vehicleEditor(.create))
        #expect(router.modal(at: 0) == .vehicleEditor(.create))
    }
}
