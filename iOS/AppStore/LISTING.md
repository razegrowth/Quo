# Quo for iPhone: App Store listing

Everything App Store Connect asks for version 1.0 (build 9), ready to paste. Limits in brackets.

## App information

- **Name** [30]: Quo Browser
- **Subtitle** [30]: The browser without the junk (28)
- **Category**: Productivity. Secondary: Utilities
- **Privacy policy URL**: https://quobrowser.com/privacy
- **Support URL**: https://quobrowser.com/support
- **Marketing URL**: https://quobrowser.com
- **Copyright**: 2026 Raze
- **Price**: Free, all countries and regions

## Promotional text [170]

A fast, quiet browser that keeps out of the way. Ads, trackers and cookie banners blocked, tabs that tidy themselves, and your Mac's spaces in your pocket.

## Description [4000]

Quo is a fast, quiet browser for people who just want to get to the page.

There's no clutter. One bar at the bottom, a + to go somewhere, and everything else tucked under ^ until you need it.

Ads, trackers and cookie banners are blocked out of the box, and tracking IDs come off the links you open. If a site breaks, one tap turns it off for that site.

Tabs you haven't touched in a while move to the Archive on their own, so the tab switcher never turns into a junk drawer.

Hold a link to see the page before you open it, with a short summary of what's on it. Ask a question about the page you're reading and get an answer from it. Messy download names like IMG_2834.pdf get a clearer one, if you want it. All of that runs on your iPhone with Apple Intelligence, so nothing you read gets sent anywhere to do it.

Search your history by what a page was about, not just its title. "That pasta recipe" finds it.

Type a site's name and go straight there. Ask a real question and Quo can send it to Perplexity or ChatGPT instead of a search page.

Use Quo on your Mac too? Your spaces, pins, bookmarks, open tabs and history come along through your own iCloud, end-to-end encrypted. Send a tab from one to the other in a tap.

Private tabs keep nothing, and can lock behind Face ID.

No account. No servers of our own. Quo counts how many people open it once a day, and you can turn that off. That's it. Everything else is on quobrowser.com/privacy.

## Keywords [100]

browser,web,private,ad blocker,tracker blocker,privacy,fast,minimal,tabs,spaces,incognito,cookie

(96 characters. No other apps' names, which Apple doesn't allow in keywords.)

## What's New [4000]

The first public version of Quo for iPhone.

## Screenshots

6.9" iPhone (1320 x 2868) in `screenshots/`, and the same at 6.3" (1206 x 2622, the size App Store Connect asks for first) in `screenshots-6.3/`.

### Order

In `iOS/AppStore/screenshots/`, in this order. Made by `design/make.py` from the app's own screens in `raw/` (run `python3 design/make.py` to remake them).

1. `1-quo.png`: The quiet browser for iPhone (the promo screen: icon, Free, four selling points)
2. `2-page.png`: The web, and nothing in the way.
3. `3-tabs.png`: Tabs that tidy themselves.
4. `4-blocking.png`: Ads, trackers and cookie banners, gone.
5. `5-toolbar.png`: Ask the page you're on.
6. `6-quiet.png`: No account. No servers. Just a browser.

## App Privacy (the "nutrition label")

- **Do you collect data?** Yes.
- **Usage Data › Product Interaction**: collected. Used for Analytics. Not linked to the user. Not used for tracking.
- **Diagnostics › Other Diagnostic Data** (device model, iOS version, app version): collected. Used for Analytics. Not linked to the user. Not used for tracking.
- Nothing else. Sync is the user's own iCloud, end-to-end encrypted, so it isn't data we collect.

This matches `iOS/Quo/PrivacyInfo.xcprivacy` and quobrowser.com/privacy.

## Age rating

Answer "None" or "No" to everything except **Unrestricted Web Access: Yes**. That alone makes it 16+ (A16 in Brazil, 15+ in Korea), the same as any browser that can open any site. Done in App Store Connect.

## Encryption

Already answered in the app (`ITSAppUsesNonExemptEncryption` is false), so App Store Connect won't ask.

## App Review information

- **Sign-in required**: No. Quo has no account.
- **Contact**: Ed's name, email and phone (fill in)
- **Notes** (rewritten for App Review's 2.1 request of 24 Nov 2026; paste everything in the box below, with the video link filled in):

```
1. SCREEN RECORDING
https://youtu.be/XvYmdsso3dY
Recorded on an iPhone Air running the latest iOS, with build 1.0 (9) from TestFlight. It starts at the Home Screen with a fresh install. Quo has no account, sign-in, user-generated content, in-app purchases or paid features, so there are none of those flows to show.

2. PURPOSE AND AUDIENCE
Quo is a web browser for anyone who wants a fast, uncluttered way to browse on iPhone. The problem it solves: pages buried under ads, cookie banners and trackers, and tab lists that pile up forever. Quo blocks ads, trackers and cookie banners out of the box, archives tabs you haven't used in a while, and offers on-device Apple Intelligence features like link previews with a short summary and asking questions about the page you're on. People who also use Quo on the Mac can sync their spaces, tabs, bookmarks and history through their own iCloud. Quo is free, with no ads and no account.

3. HOW TO USE IT
No setup, login or sample files are needed.
- Browse: tap + at the bottom, type an address or a search, and go.
- Blocking: on by default. Tap ^ to see what was blocked on the current page. "Problems? Tap to restore the original page", or Site settings, turns blocking off for that site.
- Tabs: tap the tab stack at the bottom left. Tabs untouched for a while move to the Archive at the end of the list (Settings > Archive inactive tabs).
- Link preview: touch and hold any link on a page.
- Ask this page: tap ^, then Ask this page.
- Incognito: tap + and then the glasses icon. Incognito tabs keep nothing and lock with Face ID (Settings > Lock Incognito tabs).
- Sync: Settings > Sync with Quo on your Mac. It needs Quo for Mac on the same iCloud account; without it the app works fully on its own.
The Apple Intelligence features (Ask this page, link summaries, shorter tab names, download names) only appear on devices where Apple Intelligence is available and turned on. Everything else works on every supported iPhone.

4. EXTERNAL SERVICES
- Apple iCloud (CloudKit, the user's private database): optional sync, end-to-end encrypted.
- Apple Intelligence (Foundation Models), Speech and Translation frameworks: on device.
- TelemetryDeck: a once-a-day anonymous count that the app was opened, with app version, device model and iOS version. Users can turn it off in Settings > Help count how many people use Quo.
- easylist.to and fanboy.co.nz: the public EasyList, EasyPrivacy and Fanboy's Cookie Monster filter lists that blocking is built from.
- The user's chosen search engine (Google by default): searches, and suggestions while typing.
- Perplexity and ChatGPT: only if the user picks one, a question typed in the address field opens on that site as a normal web page. No API or account.
There are no servers of our own, no authentication service, no payment processor and no ad network.

5. REGIONS
Quo works the same in every region where it's offered. The only difference comes from Apple: the Apple Intelligence features appear only where Apple Intelligence is available for the device, region and language.

6. REGULATION AND THIRD-PARTY MATERIAL
Quo isn't in a regulated industry and doesn't include protected third-party material. The filter lists are used under their open licences (GPLv3 / CC BY-SA 3.0), credited in Settings > Open source licences.

Privacy policy: https://quobrowser.com/privacy
Support: https://quobrowser.com/support
```

### The screen recording (Apple's step 1)

On Ed's iPhone (Control Center > Screen Recording), build 1.0 (9) from TestFlight, latest iOS. Delete Quo first so it starts fresh, then:

1. Start on the Home Screen and tap Quo. Go through the intro.
2. Tap +, type a news site (theverge.com or similar) and open it.
3. Tap ^ to show what was blocked, then close it.
4. Touch and hold a link to show the preview and its summary. Open it.
5. Tap ^ > Ask this page, ask something about the article.
6. Open the tab stack, show a few tabs, close one.
7. Tap +, the glasses, open a page in Incognito, then leave Incognito.
8. Open Settings, scroll through, show Sync and the usage count toggle.

About 1 to 2 minutes. Upload it somewhere Apple can watch without signing in (an unlisted YouTube video, or a shared iCloud Drive or Google Drive link) and put the link at the top of the notes. Done: https://youtu.be/XvYmdsso3dY (filed under Shorts in YouTube Studio, since it is vertical and under 3 minutes).

## Release

Pick **Manually release this version** so launch day is your call after approval.
