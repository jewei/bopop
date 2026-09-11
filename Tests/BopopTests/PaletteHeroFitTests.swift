import AppKit
import Testing
@testable import Bopop
@testable import BopopKit

private func valueLabels(in view: NSView) -> [NSTextField] {
    view.subviews.flatMap { valueLabels(in: $0) }
        + view.subviews.compactMap { $0 as? NSTextField }
}

/// Lays the card out at the real panel width and returns the right-hand value
/// label, so these tests measure the pane the user actually sees rather than an
/// arithmetic guess at its width.
@MainActor
private func laidOutHero(_ hero: HeroContent) -> NSTextField? {
    let view = PaletteHeroView()
    view.configure(with: hero)
    let host = NSView(frame: NSRect(x: 0, y: 0, width: PaletteMetrics.width, height: 120))
    host.addSubview(view)
    NSLayoutConstraint.activate([
        view.leadingAnchor.constraint(equalTo: host.leadingAnchor),
        view.trailingAnchor.constraint(equalTo: host.trailingAnchor),
        view.topAnchor.constraint(equalTo: host.topAnchor),
        view.heightAnchor.constraint(equalToConstant: PaletteMetrics.heroHeight)
    ])
    host.layoutSubtreeIfNeeded()
    view.layoutSubtreeIfNeeded()
    return valueLabels(in: view).first { $0.alignment == .right }
}

@MainActor
private func renderedLineCount(_ label: NSTextField, text: String) -> Int {
    let style = NSMutableParagraphStyle()
    style.lineBreakMode = label.lineBreakMode
    let needed = (text as NSString).boundingRect(
        with: NSSize(width: label.frame.width, height: .greatestFiniteMagnitude),
        options: [.usesLineFragmentOrigin],
        attributes: [.font: label.font!, .paragraphStyle: style]
    )
    return Int((needed.height / label.font!.boundingRectForFont.height).rounded(.up))
}

private func passwordHero(_ password: String) -> HeroContent {
    HeroContent(
        left: "\(password.count) characters",
        leftBadge: "a–z · A–Z · 0–9 · !@#",
        right: password,
        rightBadge: "128 bits · Very strong",
        note: "Kept out of history",
        rightWrapsByCharacter: true
    )
}

/// The card is what ⏎ copies. A password it renders with a trailing ellipsis is
/// a password the user can read wrongly off the screen, so every length the
/// generator can be asked for has to fit the two lines the card has room for.
///
/// This is the test that pins `PasswordQuery.lengthLimits.upperBound`. It fails
/// if that bound rises past what the smallest font can show.
/// Sampled rather than exhaustive over the whole range. Each length picks the
/// largest font that fits it, so lengths are independent and the only real
/// failure mode is the ladder bottoming out — which bites at the top. These are
/// both bounds plus every length where the chosen font steps down. Laying out
/// all 59 was 59 main-actor layouts, enough extra load to tip
/// `debounceCancellationStopsTranslate`'s documented race into failing.
@MainActor
@Test func heroCardShowsEveryGeneratablePasswordInFull() {
    let fontSteps = [33, 34, 47, 48, 63]
    for length in [PasswordQuery.lengthLimits.lowerBound, PasswordQuery.defaultLength]
        + fontSteps + [PasswordQuery.lengthLimits.upperBound] {
        let password = PasswordGenerator.generate(
            .characters(length: length, alphabet: .everything))
        #expect(password.count == length)
        guard let label = laidOutHero(passwordHero(password)) else {
            Issue.record("no value label at length \(length)")
            return
        }
        let lines = renderedLineCount(label, text: password)
        #expect(
            lines <= 2,
            "\(length) chars needs \(lines) lines at \(label.font!.pointSize)pt — the card would truncate"
        )
    }
}

/// Word wrapping breaks a password at its punctuation, which wasted most of the
/// second line and started truncating at 40 characters.
@MainActor
@Test func passwordHeroWrapsByCharacterAndProseDoesNot() {
    let password = PasswordGenerator.generate(
        .characters(length: 40, alphabet: .everything))
    #expect(laidOutHero(passwordHero(password))?.lineBreakMode == .byCharWrapping)

    let prose = HeroContent(
        left: "10:30", leftBadge: "Taipei",
        right: "Pacific Daylight Time", rightBadge: "Los Angeles"
    )
    #expect(laidOutHero(prose)?.lineBreakMode == .byWordWrapping)
}

/// Only payload heroes shrink. A calculator or timezone answer keeps the
/// original size, so this change cannot quietly restyle every other provider.
@MainActor
@Test func proseHeroKeepsTheFullSizeFont() {
    let prose = HeroContent(
        left: "1,234,567", leftBadge: "Sum",
        right: "One Million Two Hundred Thirty-Four Thousand Five Hundred Sixty-Seven"
    )
    #expect(laidOutHero(prose)?.font?.pointSize == 22)
}

/// The same view instance is reused across heroes. A password must not leave
/// its character wrapping or its shrunken font behind for the next one.
@MainActor
@Test func heroDoesNotCarryPayloadStylingIntoTheNextResult() {
    let view = PaletteHeroView()
    let host = NSView(frame: NSRect(x: 0, y: 0, width: PaletteMetrics.width, height: 120))
    host.addSubview(view)
    NSLayoutConstraint.activate([
        view.leadingAnchor.constraint(equalTo: host.leadingAnchor),
        view.trailingAnchor.constraint(equalTo: host.trailingAnchor),
        view.topAnchor.constraint(equalTo: host.topAnchor),
        view.heightAnchor.constraint(equalToConstant: PaletteMetrics.heroHeight)
    ])

    let password = PasswordGenerator.generate(
        .characters(length: 64, alphabet: .everything))
    view.configure(with: passwordHero(password))
    host.layoutSubtreeIfNeeded()
    view.layoutSubtreeIfNeeded()
    let shrunk = valueLabels(in: view).first { $0.alignment == .right }
    #expect(shrunk?.font?.pointSize != 22, "a 64-character password should have shrunk")

    view.configure(with: HeroContent(left: "2+2", right: "4"))
    host.layoutSubtreeIfNeeded()
    view.layoutSubtreeIfNeeded()
    let restored = valueLabels(in: view).first { $0.alignment == .right }
    #expect(restored?.font?.pointSize == 22)
    #expect(restored?.lineBreakMode == .byWordWrapping)
}
