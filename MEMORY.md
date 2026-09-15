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

## 2026-09-15 15:45 — Equal heights for the header sections; right inset in the Points half
- **What:**
  - The Orders / Messages / Notifications section takes the Delivery + Points card's height from one shared `DeliveryPointsCard.rowHeight`: 44 on phones, 56 on tablet/desktop. Before, a phone had card 42 / icons 44 and a tablet had 56 / 44.
  - The phone/tablet choice follows the screen width (< 600) so both sections agree.
  - The Points half has a 10 dp right inset on phones (was 4) and 14 on tablet/desktop (was 10). The inner gaps beside the divider are 2 and 4 so the address keeps its width.
- **Why:** User request: the icon section exactly matches the card's height and proportions, with comfortable right-side padding in Delivery/Points. Backgrounds and borders already matched and were not changed.
- **Affected:** `delivery_points_card.dart` (`isDense`, `rowHeight`, `pointsPadding`, dense metrics); `search_header.dart` (`_Block` min height). Tests: `header_additions_test` (exact height match on phone + new tablet test); `delivery_points_card_test` (wrapper keeps the real screen size; explicit tablet size).
- **Impact & risk:** Header row only. Icons, labels, text, colours and taps are unchanged; the icon section keeps its reduced padding and gap. Found while testing: the extra right inset truncated the address ("Ekantaku..."), fixed by tightening the inner gaps.
- **Verification:** analyze clean; header, tour and home suites 148/148. On the Redmi both sections share top and bottom edges, the address reads "Ekantakuna" in full, and "1,000 Points" is inset from the right edge.
- **Commit:** see `git log` — `style(home): level the header sections and inset the points`, pushed to origin `main`.

## 2026-09-15 15:30 — Icon section surface matches the Delivery + Points card
- **What:** The Orders / Messages / Notifications section (`_Block` in `search_header.dart`) uses the card's surface: black at 22% fill, a 1px white-12% border, radius 14. It was a white-12% wash with no border. The card has no drop shadow, so none was added; fill and border are what give it its weight.
- **Why:** User request: match the icon section's background/shadow to the Delivery and Points section.
- **Affected:** `lib/features/home/widgets/search_header.dart` (`_Block` decoration only). Icons, labels, padding, height and taps are unchanged.
- **Impact & risk:** Minimal. Visual only.
- **Verification:** analyze clean; header, tour and home suites 147/147. On the Redmi the two groups read as a matching pair.
- **Commit:** see `git log` — `style(home): give the icon section the delivery card's surface`, pushed to origin `main`.

## 2026-09-15 15:25 — Fix truncated address in the Delivery + Points card on phones
- **What:** In the card's dense (phone) form the arrows are hidden and the address shows the neighbourhood alone ("Ekantakuna"), falling back to the city. Tablet and desktop keep both arrows and "Neighbourhood, City". The screen reader always hears the full place.
- **Why:** User asked to fix "Deliver ... / Ekant..." on the Redmi, where the card shares its row with the icon section.
- **Affected:** `lib/features/home/widgets/delivery_points_card.dart` (`_Metrics.chevrons`/`placeWithCity`, `placeOf(withCity:)`). Tests: `delivery_points_card_test` (+2), `header_additions_test` (no arrows at phone width), `header_chrome_test` (neighbourhood alone at phone width).
- **Impact & risk:** Card only; icons, labels and taps are unchanged. Both halves remain tappable without the arrows.
- **Verification:** analyze clean; header, tour and home suites 147/147. On the Redmi: "Deliver to / Ekantakuna" and "1,000 Points" in full.
- **Commit:** see `git log` — `fix(home): show the whole place in the phone-width delivery card`, pushed to origin `main`.

## 2026-09-15 15:05 — Home header: Delivery + Points card; compact icon section
- **What:**
  - New `DeliveryPointsCard` from the reference: pin, "Deliver to" and the place, chevron-down | gold "P" coin, the balance, "Points", chevron-right.
  - It sits on the **same row, left of** the Orders / Messages / Notifications section. That section's padding is reduced (4/2 to 2/1) and the gap between them is 6 dp.
  - Below a 360 dp card width it uses dense metrics (42 tall, level with the icon section). Tablet and desktop use the reference size.
  - The place is built from the area line and skips the province, postcodes and the city, so a detected "Bagmati Province 44600, Ekantakuna" reads "Ekantakuna, Lalitpur".
- **Why:** User requests: add the Delivery + Points design from the reference, then keep it left of the icon section with a more compact icon section. "Points" and the "P" coin are in this card only; the wallet still says Coins.
- **Affected:**
  - New `lib/features/home/widgets/delivery_points_card.dart`
  - `search_header.dart`: the row now holds the card; the icon section padding changed
  - Tests: new `test/delivery_points_card_test.dart`; `header_chrome_test`, `header_additions_test` and `header_collapse_test` retargeted from the old `DeliveryLocationButton`/`CoinBalanceButton` to the card, with reasons in comments
  - Data is unchanged: `AddressStore.defaultAddress` and `GET /wallet` via `CoinBalanceStore`. The taps open the address picker and `WalletScreen`. The coins tour anchor moved onto the card.
- **Impact & risk:** Header layout only.
  - Found on the phone and fixed: overflow at 1.5x/2x text; "Bagmati Provin..." from a detected address.
  - Header rules kept: icons under 24, 14 dp corners inside the band.
  - Accepted trade-off: on a 406 dp phone the address truncates ("Ekant...") because the icon section keeps its labelled tiles.
- **Verification:** analyze clean. Header, tour and home suites 145/145, with no overflow at 320-406 dp and 2x text. The previous full run (before the row change) was 2335 pass, 3 known `brand_system_test` failures. On the Redmi: one row, level, address picker and points tap wired.
- **Commit:** see `git log` — `feat(home): delivery and points card beside a compact icon section`, pushed to origin `main`.

## 2026-09-15 13:15 — Remove "(Optional)" from the Location label
- **What:** The Location row label in Profile Settings reads "Location"
  instead of "Location (Optional)". Removed the now-unused `optional`
  parameter from `_FieldRow`; it had no other user.
- **Why:** User request: remove only the "Optional" text; keep the field.
- **Affected:** `lib/features/profile/presentation/profile_settings_screen.dart`
  (Location row, `_FieldRow`), `test/profile_settings_test.dart` (the
  location test now asserts no "Optional").
- **Impact & risk:** Minimal. The value, icon, "Change" button, address-book
  link and layout are unchanged.
- **Verification:** analyze clean; `profile_settings_test` 34/34; on the
  Redmi the row shows "Location / Lalitpur, Bagmati" with the Change pill.
- **Commit:** see `git log` — `style(profile): drop "(Optional)" from the
  Location label`, pushed to origin `main`.

## 2026-09-15 12:58 — Two-factor authentication (TOTP) on GoTrue
- **What:** Real 2FA using GoTrue v2.177.0 built-in MFA (`/factors`
  enroll/challenge/verify/delete). No separate 2FA system.
  - **Security → Two-Factor Authentication** (`TwoFactorScreen`):
    - status read from the server (Enabled / Not enabled / Setup incomplete)
    - turn on: password → server-generated secret → QR code and manual key
      → code verified by the server → Enabled
    - turn off: password and current code → confirm → factor deleted on the
      server → status re-read
  - **Login gate:** after a correct password or Google/Apple sign-in, an
    account with a verified factor gets `TwoFactorChallengeScreen`. The
    `aal1` session is held **in memory only**, never stored or adopted, until
    GoTrue verifies the code and issues an `aal2` session.
    - wrong code: rejected
    - expired challenge: renewed
    - cancel: the aal1 session is revoked on the server
  - Password reset for a 2FA account asks for the code before setting the
    new password.
  - Startup and account switching refuse an `aal1` session of a 2FA account.
  - Email/phone OTP verification never downgrades an `aal2` session.
  - The Profile Settings 2FA row shows the real status and opens the screen.
- **Why:** User request for real, server-verified 2FA with login integration.
  Before this, `AuthRepository.signIn` stored the session immediately, which
  would have saved password-only sessions for 2FA accounts.
- **Affected:**
  - New: `lib/features/security/data/mfa_repository.dart`, `mfa_store.dart`,
    `lib/features/security/presentation/two_factor_screen.dart`,
    `totp_code_field.dart`,
    `lib/features/auth/presentation/two_factor_challenge_screen.dart`,
    `test/two_factor_test.dart`
  - Changed: `auth_repository.dart` (signIn, completeOAuth and reset no
    longer store; `verifyRecovery`/`setPassword` split;
    `_writeKeepingAssurance`), `auth_store.dart` (`MfaRequired`,
    `completeMfa`, `cancelMfa`, startup/switch gates), `auth_screen.dart`,
    `provider_sign_in.dart`, `reset_password_screen.dart`,
    `profile_settings_screen.dart` (2FA row), `profile_settings_test.dart`
  - Untouched: the phone/email change and verification pages.
- **Impact & risk:** High. Every sign-in path changed. Accounts without 2FA
  follow the same path as before (tested).
  - No recovery codes in GoTrue: a lost authenticator needs an admin to delete
    the factor.
  - The secret is shown once, kept in memory only, never logged or persisted.
- **Verification:**
  - Automated: `flutter analyze` clean; 18 new 2FA tests; full suite 2326
    pass, 3 known `brand_system_test` failures; profile + 2FA + phone suites
    70/70 after the width change.
  - Found and fixed: `MfaStore` notified listeners during a build.
  - **NOT YET DONE — live end-to-end test on the phone and in Chrome** (enable
    → sign out → sign in with challenge → wrong/right code → disable). The
    user asked to commit before it. Waiting on a test account and Microsoft
    Authenticator.
  - **NOT YET DONE — gateway probe:** whether the Go gateway rejects `aal1`
    tokens for 2FA accounts. Until checked, the website/API may accept a
    password-only token. **Open risk.**
- **Commit:** see `git log` — `feat(security): two-factor authentication with
  GoTrue TOTP`, pushed to origin `main`.

## 2026-09-15 12:50 — Profile Settings responsive width; "Change" label
- **What:** The page width now depends on screen size, set in the new
  `_PageFrame` helper:
  - phone (< 600 dp): 1.5% margin each side, about **97%** width
  - tablet (600–1024 dp): 24 dp margins, centred column capped at **680**
  - desktop (1024+ dp): 24 dp margins, centred column capped at **720**

  Row pills changed from "Edit" to **"Change"**.
- **Why:** User request. The rendered column was a fixed 16 dp margin plus a
  620 cap: 374 of 406 dp on the phone (92%), and a narrow 620 column on
  desktop.
- **Affected:**
  - `lib/features/profile/presentation/profile_settings_screen.dart`: the
    ListView padding and ConstrainedBox cap (the real width constraints),
    `_EditPill` label, new `_PageFrame`
  - `test/profile_settings_test.dart`: the pill test now expects "Change";
    new tests measure the rendered column at 406 / 800 / 1400 dp
  - Untouched: typography, colours, icons, the phone/email change pages and
    their navigation, routing, backend.
- **Impact & risk:** Low. Only outer width and one word. The inner
  breakpoints (`_sideBySideFrom` 420, `_chipBesideFrom` 460) still hold on
  a 394 dp phone column.
- **Verification:** analyze clean. Profile and phone verification suites
  50/50. On the Redmi: about 6 dp margins, full name on one line, four
  "Change" pills.
- **Note:** The uncommitted 2FA work (waiting on the live phone test) was
  kept out of this commit.
- **Commit:** see `git log` — `style(profile): responsive page width and
  "Change" label`, pushed to origin `main`.

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
