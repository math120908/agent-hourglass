import Foundation

/// Spec §11 JSON shape, written by hand so key order is stable for golden tests.
extension Exporter {
    func json(accounts: [AccountEntry], range: DateInterval?, appVersion: String) async throws -> Data {
        var out = "{\"exportedAt\":\(Self.str(Self.iso(Int64(now().timeIntervalSince1970.rounded(.down))))),"
        out += "\"app\":\(Self.str("claude-usage \(appVersion)")),\n\"accounts\":["
        for (i, a) in accounts.enumerated() {
            if i > 0 { out += "," }
            out += "\n{\"id\":\(Self.str(a.id.rawValue)),\"name\":\(Self.str(a.displayName)),\"provider\":\(Self.str(a.kind.rawValue)),\n\"series\":{"
            var spend: [String] = []
            var meter: String?
            var first = true
            try await forEachRow(account: a.id, range: range) { r in
                if r.meter == "spend" {
                    var o = "{\"t\":\(Self.str(Self.iso(r.ts)))"
                    if let u = r.used { o += ",\"used\":\(u)" }
                    if let l = r.limit { o += ",\"limit\":\(l)" }
                    if let c = r.unit { o += ",\"currency\":\(Self.str(c))" }
                    spend.append(o + "}")
                    return
                }
                if r.meter != meter {
                    if meter != nil { out += "]," }
                    out += "\n\(Self.str(r.meter)):["
                    meter = r.meter
                    first = true
                }
                out += (first ? "\n" : ",\n") + "{\"t\":\(Self.str(Self.iso(r.ts)))"
                first = false
                if let p = r.percent { out += ",\"percent\":\(Self.num(p))" }
                if let u = r.used { out += ",\"used\":\(u)" }
                if let l = r.limit { out += ",\"limit\":\(l)" }
                if let s = r.resetsAt { out += ",\"resetsAt\":\(Self.str(Self.iso(s)))" }
                if r.hourly { out += ",\"rollup\":\"hourly\"" }
                out += "}"
            }
            if meter != nil { out += "]" }
            out += "},\n\"spend\":[" + spend.map { "\n" + $0 }.joined(separator: ",") + "]}"
        }
        out += "]}\n"
        return Data(out.utf8)
    }

    static func str(_ s: String) -> String {
        var o = "\""
        for u in s.unicodeScalars {
            switch u {
            case "\"": o += "\\\""
            case "\\": o += "\\\\"
            case "\n": o += "\\n"
            case "\r": o += "\\r"
            case "\t": o += "\\t"
            default:
                if u.value < 0x20 { o += String(format: "\\u%04x", u.value) } else { o.unicodeScalars.append(u) }
            }
        }
        return o + "\""
    }
}
