# Feedless

A distraction-free wrapper around Instagram's mobile web for iPhone. It loads instagram.com in a WKWebView with a Safari user agent, always opens the Following feed (or Favorites, your choice), and hides Reels, Explore, suggested posts and accounts, sponsored posts, and the stories tray. Each category can be switched off in Settings, which opens when you shake the phone; the app adds no chrome of its own around Instagram. No third-party code, no analytics, no account of its own.

## Install

Requires Xcode 16 or later with the iOS 17 SDK and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen
```

```bash
git clone https://github.com/mironable/feedless.git && cd feedless
```

```bash
xcodegen generate
```

Open `Feedless.xcodeproj`, pick your team under Signing, select your iPhone and run. The `.xcodeproj` is generated and not committed; rerun `xcodegen generate` after adding files.

Run the tests on a simulator:

```bash
xcodebuild -project Feedless.xcodeproj -scheme Feedless -destination 'platform=iOS Simulator,name=iPhone 16' test
```

## Prerequisite: the Instagram app

Instagram's web client does not serve view-once photos and videos or some voice messages in DMs. Feedless replaces those placeholders with an "Open in Instagram app" button that opens the thread in the official app via `instagram://direct/t/<thread_id>`, so keep the Instagram app installed. If it is missing, the button falls back to the web URL, which shows the same placeholder.

## Message alerts

Instagram only pushes notifications to its own app and to browsers, never to a web view inside another app, so Feedless cannot receive them. Instead, with "New message alerts" on in Settings, Feedless asks iOS for background refresh and, whenever iOS grants it (typically a few times an hour, never on a fixed schedule), fetches your inbox with the web view's session and posts a local notification for each thread with a new message. Tapping the alert opens that thread. Expect 15 to 60 minutes of delay, and expect it to break when Instagram changes its inbox API. With this on you can silence the official app entirely.

## How the rules work

Everything Instagram-specific lives in `Feedless/Resources/Rules/instagram/`:

- `manifest.json` lists hosts, feeds and the toggleable categories.
- `instagram.css` hides elements by href, role and aria-label. Every rule is scoped to an `html[data-fl-<category>]` attribute, so toggling a category in Settings flips an attribute instead of reloading.
- `instagram.js` watches the DOM for sponsored and suggested blocks, keeps the feed on Following, redirects in-page navigation to Reels or Explore back home, and adds the hand-off button in DMs.
- `instagram.rules.json` is a WKContentRuleList that blocks ad and tracking requests. It is compiled once and cached.

Updating a selector is a text-file change. Adding another platform is a new folder with the same four files.

## Disclaimer

Feedless is not affiliated with, endorsed by or connected to Meta Platforms, Inc. or Instagram. It is a browser that loads instagram.com and relies on the structure of Instagram's web layout, which Instagram changes without notice; when that happens, rules may stop matching and some hidden elements may reappear until the rule files are updated. The bundled test fixture is a hand-written approximation of that layout, so a green test run proves the rules match the fixture, not that they still match instagram.com. Use at your own risk and in line with Instagram's terms of service.

## License

MIT, see [LICENSE](LICENSE).
