import Testing
@testable import UsageCore
@testable import UsageCoreMac

@MainActor
final class FakeLoginService: LoginItemService {
    var status: LoginItemStatus
    var onRegister: LoginItemStatus = .enabled
    var fail = false
    var calls: [String] = []
    init(_ s: LoginItemStatus) { status = s }
    struct Boom: Error {}
    func register() throws {
        calls.append("register")
        if fail { throw Boom() }
        status = onRegister
    }
    func unregister() throws {
        calls.append("unregister")
        if fail { throw Boom() }
        status = .notRegistered
    }
}

@MainActor
@Suite struct LoginItemTests {
    @Test func readsStatusOnInit() {
        #expect(LoginItem(service: FakeLoginService(.enabled)).isEnabled)
        #expect(!LoginItem(service: FakeLoginService(.notRegistered)).isEnabled)
    }

    @Test func toggleOnAndOff() {
        let fake = FakeLoginService(.notRegistered)
        let item = LoginItem(service: fake)
        item.set(true)
        #expect(item.isEnabled && item.status == .enabled)
        item.set(false)
        #expect(!item.isEnabled)
        #expect(fake.calls == ["register", "unregister"])
    }

    @Test func requiresApprovalSurfaces() {
        let fake = FakeLoginService(.notRegistered)
        fake.onRegister = .requiresApproval
        let item = LoginItem(service: fake)
        item.set(true)
        #expect(item.needsApproval && item.isEnabled)
    }

    @Test func toggleReflectsStatus() {
        // App moved after registering: the service reports notFound; refresh must not keep a stale true.
        let fake = FakeLoginService(.enabled)
        let item = LoginItem(service: fake)
        fake.status = .notFound
        item.refresh()
        #expect(!item.isEnabled)
    }

    @Test func failureKeepsRealStatusAndReportsError() {
        let fake = FakeLoginService(.notRegistered)
        fake.fail = true
        let item = LoginItem(service: fake)
        item.set(true)
        #expect(!item.isEnabled)
        #expect(item.lastError != nil)
    }
}
