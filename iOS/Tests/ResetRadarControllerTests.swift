import Foundation
import UserNotifications
import Testing
import UsageCore
@testable import AgentHourglass

@Test func resetRadarRefreshRequestUsesPlanIDAndOneHour() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let r = ResetRadarController.refreshRequest(now: now)
    #expect(r.identifier == "cc.kuoc.agent-hourglass.reset-radar")
    #expect(r.earliestBeginDate == now.addingTimeInterval(3600))
}

@Test func resetRadarTaskIDIsPermittedInInfoPlist() {
    let ids = Bundle.main.object(forInfoDictionaryKey: "BGTaskSchedulerPermittedIdentifiers") as? [String]
    #expect(ids?.contains(ResetRadarController.taskID) == true)
    let modes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String]
    #expect(modes?.contains("fetch") == true)
}

@MainActor @Test func resetRadarSettingsDefaultsAndRoundTrip() {
    let suite = "test.\(UUID().uuidString)"
    let c = ResetRadarController(defaults: UserDefaults(suiteName: suite)!)
    #expect(c.settings == ResetRadarSettings(show: true, notify: true, notifyCredits: false))
    c.settings = ResetRadarSettings(show: false, notify: false, notifyCredits: true)
    let d = UserDefaults(suiteName: suite)!
    #expect(d.bool(forKey: "resetRadar.show") == false)
    #expect(d.bool(forKey: "resetRadar.notify") == false)
    #expect(d.bool(forKey: "resetRadar.notifyCredits") == true)
    #expect(ResetRadarController(defaults: d).settings == c.settings)
}

@Test func resetRadarUserAgentMatchesPlan() {
    #expect(ResetRadarController.userAgent.hasPrefix("AgentHourglass/"))
    #expect(ResetRadarController.userAgent.hasSuffix(" (+https://github.com/math120908/agent-hourglass)"))
}

@MainActor @Test func resetRadarEntriesMarkConfirmed() {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC")!
    let at = Date(timeIntervalSince1970: 1_793_169_338) // 2026-10-28T06:35:38Z
    let c = ResetRadarController(events: [
        ResetEvent(id: "a", day: "2026-10-28", kind: .reset, summary: "s", url: nil, at: at, confirmed: true),
        ResetEvent(id: "b", day: "2026-10-26", kind: .credits, summary: "t", url: nil, at: nil, confirmed: false),
    ], defaults: UserDefaults(suiteName: "test.\(UUID().uuidString)")!)
    let e = c.entries(calendar: cal)
    #expect(e.map(\.meta) == ["Oct 28 06:35 | confirmed", "Oct 26"])
    #expect(e[1].isCredits)
}

@MainActor @Test(arguments: [
    (true, UNAuthorizationStatus.notDetermined, 1),
    (true, UNAuthorizationStatus.denied, 0),
    (true, UNAuthorizationStatus.authorized, 0),
    (false, UNAuthorizationStatus.notDetermined, 0),
])
func resetRadarForegroundAsksPermissionOnlyWhenUndetermined(notify: Bool, status: UNAuthorizationStatus, asks: Int) async {
    let requests = Counter()
    let auth = ResetRadarController.NotificationAuth(status: { status }, request: { await requests.bump() })
    let c = ResetRadarController(defaults: UserDefaults(suiteName: "test.\(UUID().uuidString)")!, auth: auth)
    if !notify { c.settings.notify = false }
    await requests.reset()
    await c.sceneBecameActive()
    #expect(await requests.value == asks)
}

private actor Counter {
    var value = 0
    func bump() { value += 1 }
    func reset() { value = 0 }
}
