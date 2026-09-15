# MEMORY — gtradea-amazon task log

What was done in this repo, why, and what it touched. **Newest first.**
Every completed task adds an entry here, is committed, and is pushed to
origin.

Entry format:

```
## YYYY-MM-DD HH:MM — <task title>
- **What:** what was done
- **Why:** the request / problem it solves
- **Affected:** files / features / screens touched
- **Impact & risk:** what could break, what was checked
- **Verification:** analyze / test / device results
- **Commit:** <hash> on <branch>, pushed to origin
```

---

## 2026-09-15 12:10 — Profile Settings matched to the reference design
- **What:** Refined `ProfileSettingsScreen` to the supplied reference:
  - round gear in the header (menu: Theme, Language, Notifications)
  - circular icon discs
  - "Edit" pills with a hairline border (was "Change")
  - new **Location (Optional)** row: the default delivery address; Edit opens
    the address book
  - new **Two-Factor Authentication (2FA)** row, "Not enabled", with an honest
    "isn't available yet" message
  - tappable safety banner that opens the privacy policy
  - white ring on the avatar
  - Nunito Sans type scale local to this page
  - cool page ground (teal at 3% over white)
  - name wraps to 2 lines; values shrink rather than truncate
  - on narrow widths the status chip sits under the row note
- **Why:** User request: match the reference exactly. Decisions: no "Member
  since", no "Verified" badges, no Profile Preferences. "Edit" label.
  Location and 2FA rows added. Reference font on this page only.
- **Affected:**
  - `lib/features/profile/presentation/profile_settings_screen.dart`
  - `pubspec.yaml` (fonts entry)
  - `assets/fonts/NunitoSans-VariableFont.ttf` + `NunitoSans-OFL.txt`
  - `test/profile_settings_test.dart` (+7 tests)
  - Untouched: the phone/email change and verification pages and their
    navigation, the name/password sheets, photo upload, Login Activity.
- **Impact & risk:** Low. One screen; the font is page-local. The APK grows by
  about 0.57 MB.
- **Verification:** `flutter analyze` clean. Profile, phone verification and
  photo sync suites: 52/52 pass. Full suite: 2306 pass, 3 known
  `brand_system_test` failures (unchanged). On the phone (Redmi): header, rows,
  2FA chip and banner checked against the reference; Phone "Edit" opens the
  existing Change Phone Number page.
- **Commit:** see `git log` — `feat(profile): match Profile Settings to the
  reference`, pushed to origin `main`.

## 2026-09-15 11:22 — Merge all branches into main; start this log
- **What:** Fast-forwarded local `main` to `origin/main` (`9e677ec`), then
  merged `feat/sep-11-15-features` with a `--no-ff` merge commit.
  `feat/support-attachments-and-visual-search` was already contained in
  `main`. Branches were kept. Added this MEMORY.md.
- **Why:** The Sep 5–15 work existed only on a backup branch; `main` was
  three weeks stale locally. Requested: all branches merged to main with
  proper commit and merge information, and a task log going forward.
- **Affected:** `main` only. No code changed by the merge itself; the tree
  is identical to `feat/sep-11-15-features` (`874f80f`).
- **Impact & risk:** Low. A straight line of history, so no conflicts.
- **Verification:** `flutter analyze`: no issues. `flutter test`: 2299
  pass, **3 fail** in `test/brand_system_test.dart` (they still expect the
  removed Premium Ivory six-colour palette). Pre-existing on the branch,
  not caused by the merge. **Open: update those tests.**
- **Commit:** merge `05793ac` on `main`, pushed to origin.

## 2026-09-15 10:55 — Back up the Sep 5–15 work
- **What:** Committed 257 files that existed only in the working tree to
  new branch `feat/sep-11-15-features` and pushed it.
- **Why:** Almost two weeks of work was uncommitted and at risk of loss.
- **Affected:** Everything listed in the section below.
- **Verification:** Scanned for secrets and files over 1 MB before
  committing — none. Built and installed on the phone.
- **Commit:** `874f80f` on `feat/sep-11-15-features`, pushed to origin.

## 2026-09-05 → 2026-09-15 — Work summary (reconstructed from Claude session logs)
Before this log existed. Grouped by day; everything below is in `874f80f`
unless noted.
- **Sep 5–6:** Product details cleanup (removed "Hassle free / Pay when you
  receive / Trusted products", highlights section, typography, minimum
  order, no stale data flash, summary card, collapsible specs and detail
  images). Checkout phone field and "How to Pay" guide. Brand colours.
  Order details redesign and order status colours.
- **Sep 7–9:** Header and home work (search header, coin balance button,
  order tracker button), product logistics.
- **Sep 10:** Compact product detail layout, message image attachments,
  full-screen product video, cart recommendations, website orders missing
  in the app, cart "Not saved to your account" fix, tier pricing,
  login/signup in card, Continue with Apple.
- **Sep 11:** Login and signup redesign, search result cards, input text
  contrast, scroll jitter fix, invoices and receipts, homepage load speed,
  Login Activity, Theme setting, notification settings controls,
  multi-account management, profile photo sync.
- **Sep 12:** Request-to-Stock, MOQ pricing, messages redesign with status
  tags, startup black-screen fix, header hide on scroll, advanced reorder,
  Sound setting, first-time app tour, coins balance.
- **Sep 13:** New for You tab and page, Coins/Rewards page, header spacing
  and image transition, Future Cart page.
- **Sep 14:** Future Cart banner and in-cart controls, expired-session fix,
  branded push notifications (commit `9e677ec`, pushed). Profile Settings
  from the reference — "Verified" badges and "Member since" removed on
  request, "Change" instead of "Edit" — with phone and email verification
  (dummy OTP). Startup loading screen.

## Notes
- **This is the real app.** `gtradea-flutter/gtradea-amazon/` is a stale
  Sep 1 copy. Building it installs over this app on the phone (same
  package `com.gtradea.gtradea_amazon`) — that happened on Sep 15.
- Android release builds are signed with the debug key
  (`android/app/build.gradle.kts`); there is no release keystore yet.
