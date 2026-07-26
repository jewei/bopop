import Foundation
import Testing
@testable import Bopop

/// `.openURL` payloads reach NSWorkspace from user-authored custom-search
/// templates, so this allowlist is the app's guard against a template that
/// tries to launch something other than a web page.
@Test func allowedURLAcceptsOnlyWebAndDictionarySchemes() {
    #expect(ActionRunner.allowedURL(from: "https://example.com/x?q=1") != nil)
    #expect(ActionRunner.allowedURL(from: "http://example.com") != nil)
    #expect(ActionRunner.allowedURL(from: "dict://word") != nil)
}

@Test func allowedURLRejectsEverythingElse() {
    for rejected in [
        "file:///etc/passwd",
        "ftp://example.com",
        "javascript:alert(1)",
        "x-apple-systempreferences://",
        "mailto:someone@example.com",
        "",
        "not a url at all"
    ] {
        #expect(ActionRunner.allowedURL(from: rejected) == nil, "\(rejected) should be rejected")
    }
}

/// URL(string:) preserves the case it was given, so an uppercase scheme used
/// to fall through the guard and silently do nothing.
@Test func allowedURLIsCaseInsensitiveOnScheme() {
    #expect(ActionRunner.allowedURL(from: "HTTPS://example.com") != nil)
    #expect(ActionRunner.allowedURL(from: "FILE:///etc/passwd") == nil)
}
