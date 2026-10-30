import Foundation
import Testing
@testable import UsageCore

struct ResponseShapeTests {
    private func shape(_ json: String, keep: Set<String> = []) -> String {
        ResponseShape.describe(Data(json.utf8), keep: keep)
    }

    @Test func keepsNumbersAndKeptStrings() {
        let out = shape(#"{"bucketId":"gemini-5h","remainingFraction":0.62}"#, keep: ["bucketId"])
        #expect(out.contains(#""bucketId":"gemini-5h""#))
        #expect(out.contains("0.62"))
    }

    @Test func redactsUnkeptStrings() {
        let out = shape(#"{"displayName":"Gemini"}"#)
        #expect(out.contains(#""<str 6>""#))
        #expect(!out.contains("Gemini"))
    }

    @Test func redactsSensitiveKeysEvenWhenKept() {
        let keys: Set<String> = ["access_token", "id_token", "email", "cloudaicompanionProject", "refresh_token"]
        let out = shape(
            #"{"access_token":"ya29.x","id_token":"e.y.z","email":"a@b.c","cloudaicompanionProject":"aicode-consumers","refresh_token":"1//r"}"#,
            keep: keys
        )
        for leaked in ["ya29.x", "e.y.z", "a@b.c", "aicode-consumers", "1//r"] {
            #expect(!out.contains(leaked), "leaked \(leaked)")
        }
        #expect(out.contains(#""email":"<redacted>""#))
        let apiKeys = shape(#"{"apiKey":"AIza-1","api_key":"sk-2"}"#, keep: ["apiKey", "api_key"])
        #expect(apiKeys.contains(#""apiKey":"<redacted>""#) && apiKeys.contains(#""api_key":"<redacted>""#))
        #expect(!apiKeys.contains("AIza-1") && !apiKeys.contains("sk-2"))
    }

    @Test func redactsSensitiveContainers() {
        let out = shape(#"{"project":{"id":"p-1","n":3},"codes":[1],"user_code":42,"sub":["s"]}"#, keep: ["id", "sub"])
        #expect(out == #"{"codes":[1],"project":"<redacted>","sub":"<redacted>","user_code":"<redacted>"}"#)
    }

    @Test func sortedAndDeterministic() {
        let json = #"{"zeta":1,"alpha":{"y":true,"b":null},"mid":"x"}"#
        let a = shape(json), b = shape(json)
        #expect(a == b)
        #expect(a == #"{"alpha":{"b":null,"y":true},"mid":"<str 1>","zeta":1}"#)
    }

    @Test func truncatesLongArrays() {
        let nums = (1...25).map(String.init).joined(separator: ",")
        let out = shape("[\(nums)]")
        #expect(out == "[" + (1...20).map(String.init).joined(separator: ",") + #","…+5"]"#)
    }

    @Test func nonJSON() {
        #expect(ResponseShape.describe(Data("<html>".utf8)) == "<non-json 6 bytes>")
    }
}
