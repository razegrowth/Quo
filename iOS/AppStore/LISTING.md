# Quo for iPhone: App Store listing

Everything App Store Connect asks for version 1.0 (build 9), ready to paste. Limits in brackets.

## App information

- **Name** [30]: Quo Browser
- **Subtitle** [30]: The browser without the junk (28)
- **Category**: Productivity. Secondary: Utilities
- **Privacy policy URL**: https://quobrowser.com/privacy
- **Support URL**: https://quobrowser.com
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

Answer "None" to everything except **Unrestricted Web Access: Yes**, which makes it 18+. Every browser gets that.

## Encryption

Already answered in the app (`ITSAppUsesNonExemptEncryption` is false), so App Store Connect won't ask.

## App Review information

- **Sign-in required**: No. Quo has no account.
- **Contact**: Ed's name, email and phone (fill in)
- **Notes**:

> Quo is a web browser. There's no account or sign-in, so everything can be tried straight away.
>
> Some features are optional and depend on the device or the user's setup:
>
> - Ask this page, link summaries, shorter tab names and download names use Apple Intelligence on the device. They only appear where Apple Intelligence is available and turned on.
> - Sync with Quo on the Mac goes through the user's own iCloud. Without a Mac running Quo, the app works fully on its own; the spaces screen just says how to turn it on.
> - Ad, tracker and cookie-banner blocking uses content blocking rules made from public filter lists (EasyList, Fanboy).
>
> Nothing the user browses is sent to us. Privacy policy: https://quobrowser.com/privacy

## Release

Pick **Manually release this version** so launch day is your call after approval.
