import SwiftUI
import UsageCore

#Preview("Glass collapsed") {
    PopoverRoot(theme: .glass) { Fixtures.content() }
}

#Preview("Glass expanded") {
    let c = Fixtures.content()
    return PopoverRoot(theme: .glass, initiallyExpanded: Set(c.accounts.map(\.id))) { c }
}

#Preview("Glass statuses") {
    var c = Fixtures.content()
    let base = c.accounts[0]
    let extra: [AccountStatus] = [.stale, .needsLogin, .offline, .schemaError, .ghMissing, .noData]
    for (i, s) in extra.enumerated() {
        var a = base
        a.id = AccountID(kind: .claude, remoteID: "s\(i)")
        a.name = "Status \(i)"
        a.status = s
        c.accounts.append(a)
    }
    return PopoverRoot(theme: .glass) { c }
}
