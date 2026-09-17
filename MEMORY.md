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

## 2026-09-17 22:25 — Saved items: Add to Cart animation, and red heart on the summary card
- **What:**
  - **Animated button.** New `lib/features/wishlist/presentation/saved_add_to_cart_button.dart` (`SavedAddToCartButton`), used only on the Saved items card.
    - On tap, the "Add to cart" label fades and slides right while the cart icon travels left→right across the button (650 ms, easeInOutCubic, slight mid-flight scale, fades at the end).
    - The price lookup runs alongside. When both finish the real `CartStore.add` is made, and only if the line is then in the cart does the button read "✓ Added to Cart".
    - No price means the add doesn't happen. The icon runs back (280 ms), the button reads "Add to cart" again, and the existing "no price yet" message shows.
    - "Added" is read from `CartStore.contains`, so Undo or removal elsewhere resets the button. Tapping "Added to Cart" opens the cart.
  - **Single add no longer removes the card.** It used to move the item (add + unsave). The spec says the saved card must stay, so single add is now add-only, with Undo removing from the cart only. "Move all" is unchanged and still moves everything.
  - **Summary card heart.** The heart circle on the "N items saved / Move all" card is now `AppColors.wishlist` red (filled heart, 12% red circle) instead of trust blue (`_RoundIcon` takes an optional colour). The "Looking for more?" icon stays blue.
- **Why:** the user specified the Saved-items-only Add to Cart animation, and asked for red on the summary heart and its background.
- **Affected:** `wishlist_screen.dart`, the new `saved_add_to_cart_button.dart`, and `test/wishlist_test.dart` (move tests became "keeps its card and reads Added to Cart" with a mid-flight check, undo resets the button, the failed add resets the button, the badge counts after landing). Cart store, other pages' buttons and the cart flight are untouched.
- **Verification:**
  - Wishlist tests: 25 pass; analyze is clean.
  - On the Redmi: the summary heart is red. An item already in the cart reads "Added to Cart".
  - Tapped Hair Dryer: the mid-flight frame shows no label, the icon halfway across and the badge still 17. After landing the badge is 18, the button reads "Added to Cart" and the card stays.
  - Undo sets the badge back to 17 and the button back to "Add to cart".
- **Commit:** see git log on main, pushed to origin

## 2026-09-17 22:05 — Saved items: "Looking for more?" card and Browse button made visible
- **What:** in `wishlist_screen.dart`:
  - `_KeepShoppingCard` is now a white card with the standard border, matching the saved-item cards. It was a 50% grey wash.
  - Browse is a `FilledButton` (app blue) instead of `OutlinedButton`.
  - The list's bottom padding adds the system inset, so the last card clears the gesture bar.
- **Why:** the user reported the card and its Browse button were not visible. On the Redmi the card was grey-on-grey, and the outlined button's border was the same grey as the card, so Browse read as loose text. The card also sat on the gesture bar.
- **Affected:** `lib/features/wishlist/presentation/wishlist_screen.dart` (Saved items page only).
- **Verification:** 25 wishlist tests pass; analyze is clean. On the Redmi: Saved → scrolled to the end → white card with a solid blue Browse button above the gesture bar → Browse opened Categories.
- **Commit:** see git log on main, pushed to origin

## 2026-09-17 19:50 — Coins page redesigned from the "My Coins" mock-up
- **What:** `WalletScreen` body rebuilt to the user's design. The AppBar title is "My Coins"; bottom nav, header chip and data code are untouched.
  - **Balance card:** peach→blue gradient with a drawn gold "G" coin, "Your Coins", the real balance, a "≈ NPR" chip and a white Refresh pill. The stand-in picture on the right fades in softly.
  - **Info card:** "Coins are added once an order is delivered…", with "Learn more ›" opening a "How coins work" sheet.
  - **"Redeem Your Coins":** a 2-column grid (1 column under 330 dp) of 8 tinted reward cards. Each has a coloured icon badge, name, detail, coin cost and chevron.
  - **Bottom banner:** a stand-in image.
  - **Activity:** the real history list stays below.
- **Placeholders (stated plainly):**
  - Hero picture `gift_banner.jpg` and bottom banner `promo_banner.jpg` are stand-ins until the user supplies artwork (`WalletScreen.heroBannerAsset` / `bottomBannerAsset`).
  - The 8 rewards and their costs are illustrative. No endpoint exists for them (`/rewards` etc. are 404).
  - The NPR rate is `_nprPerCoin = 0.1`, from the design, not a published rate.
  - Tapping a reward still shows "Redeeming coins is not available yet." and never fakes a redemption.
- **Removed:** the old "Earn coins" list, the old 3-reward list and the "How coins work" section. That text moved into the Learn more sheet.
- **Why:** the user supplied the layout and asked for it on the Coins page, with random banners for now.
- **Affected:** `lib/features/wallet/presentation/wallet_screen.dart`, `test/wallet_screen_test.dart` (title expectation, plus a new test for rewards, learn more and banner).
- **Fixes found on the way:**
  - The hero image was laid out unbounded (`Positioned.fill(left: null)`).
  - Refresh overflowed by 0.46 px at 320 dp.
  - The hero picture first cut in hard beside "1,000" with dark corners. Now it is narrower, with a longer fade and a 1.15× crop.
- **Verification:**
  - Wallet and header tests: 21 pass. Analyze is clean.
  - On the Redmi, Points chip → My Coins: balance card, info card and 8 reward cards show, then the banner and the activity state.
  - Learn more opens the sheet; tapping a reward shows the not-available snackbar.
- **Commit:** see git log on main, pushed to origin

## 2026-09-17 19:22 — Qty box in the options popup gets a solid background
- **What:** the options popup's quantity stepper (`_QuantityRow` in `add_to_cart_sheet.dart`) sits on the card surface (white) with the same border. It is now a shaped `Material` instead of a bordered `Container`, so the −/+ ripple still draws above the fill.
- **Why:** the user asked for the Qty background to match the size boxes, which were just made solid.
- **Affected:** `lib/features/cart/presentation/add_to_cart_sheet.dart`.
- **Verification:** 21 popup tests pass; analyze is clean. On the Redmi, polo options popup → picked L → tapped + → the Qty box is white and reads 2.
- **Commit:** see git log on main, pushed to origin

## 2026-09-17 19:15 — Size option boxes get a solid background
- **What:** `OptionChips` (the text size boxes: S, M, L, XL…) now fill with the card surface (white). A selected box fills with a faint primary tint over white. Before, unselected boxes were transparent.
- **Why:** the user reported the size boxes' background wasn't visible. On the grey options sheet a transparent box with a thin border read as bare letters.
- **Affected:** `lib/features/product/widgets/option_chips.dart`, used by the options popup (`add_to_cart_sheet.dart`) and the product page `VariantPicker`.
- **Impact & risk:** fill only. Borders, sizes, disabled strike-through and the selected outline are unchanged.
- **Verification:**
  - 116 related tests pass; analyze is clean.
  - On the Redmi, the polo options popup showed M, L, XL, 2XL and 3XL as white boxes. Tapping L gave a blue outline and a tinted box.
- **Commit:** see git log on main, pushed to origin

## 2026-09-17 18:55 — Size guide & recommendation use the app's Commerce Orange, never as a fill
- **What:**
  - `SizeGuideSheet.accent` is now `AppColors.commerceOrange` (#E94724), replacing the reference's #FF7A00. This covers the figure lines, pills, ruler pointers, headline, result size and links.
  - "Size guide" button: orange icon and label on the same neutral pill.
  - No orange backgrounds:
    - Submit is an outlined button with an orange edge and label.
    - The recommendation IN/CM selection is an orange outline and text.
    - The result card is on the surface colour with an orange border.
    - The chosen row in the size table uses a neutral tint.
- **Why:** the user asked for the app's orange on the Size guide label and throughout both sections, but not as a background.
- **Affected:** `size_guide_sheet.dart`, `size_recommendation.dart`.
- **Verification:**
  - Size tests pass; analyze is clean. Only the 3 old `brand_system_test` failures remain.
  - On the Redmi: the polo options popup shows the orange "Size guide" label. The guide figures are in brand orange. On the recommendation tab, Swipe title, CM outline, pointers, result border/XS and "See XS" link are orange, and Submit/Saved is outlined, with no orange fills.
- **Commit:** see git log on main, pushed to origin

## 2026-09-17 18:40 — Size recommendation: result only from Submit, for the selected values
- **What:**
  - Opening the tab no longer shows the suggestion saved earlier. The rulers start on the saved values, and the result appears only when Submit is tapped.
  - Moving either ruler removes the result, replacing the faded "Measurements changed" card.
  - The card now starts with "Based on your bust X cm and waist Y cm", naming exactly the values it used.
- **Why:** the user asked that Submit give the result based on the selected bust and waist sizes. A suggestion showing before Submit, or left over from other numbers, looked unrelated to what was selected.
- **Affected:** `size_recommendation.dart` (`_measured`, `_Result.basedOn`, stale UI removed), `test/size_recommendation_test.dart`.
- **Verification:**
  - 12 recommendation tests pass; analyze is clean.
  - On the Redmi: polo → Size guide → Size recommendation opened with no result, on the saved 114 / 58 cm.
  - Submit showed "Based on your bust 114 cm and waist 58 cm", XXL, with ✓ Saved.
  - Moving the waist ruler to 76 removed the card.
  - Submit again showed "Based on your bust 114 cm and waist 76 cm", XXL (waist fits S).
- **Commit:** see git log on main, pushed to origin

## 2026-09-17 12:45 — Size recommendation: Submit gives visible feedback
- **What:**
  - Submit now turns into "✓ Saved" for 1.6 s, and the result card flashes orange on every Submit.
  - Moving a ruler after a suggestion fades the card and shows "Measurements changed. Tap Submit to update your size."
  - The "Saved" reset uses a cancellable `Timer`.
- **Why:** the user reported "Submit not works". On the phone, Submit did save and recompute: the card went from "Bust below the smallest standard size" to "Bust fits XS", and there were no errors in logcat. The problem was that nothing showed it worked. When the size stayed the same the card barely changed, and after a ruler moved the old answer still looked current.
- **Affected:** `size_recommendation.dart` (`_submitted`, `_changed`, `_justSaved`, `_flash`; `_Result` `stale`/`flash`), `test/size_recommendation_test.dart` (+1 test).
- **Impact & risk:** only this tab's presentation changed. The suggestion logic and storage are the same.
- **Verification:**
  - 12 recommendation tests pass; analyze is clean.
  - The APK is installed on the Redmi. I haven't tapped through the new feedback there yet, because the phone was in use (landscape home screen).
- **Commit:** see git log on main, pushed to origin

## 2026-09-17 12:30 — Size recommendation tab
- **What:** the size guide sheet now has two tabs in its header, "Size guide" and "Size recommendation". The new tab is in `lib/features/product/widgets/size_recommendation.dart` and follows the Temu reference:
  - "Swipe to add your body information", an orange IN/CM switch, and Bust / Waist rows. Each row has a value box and a horizontal ruler that snaps to ticks under an orange pointer (`RulerPicker`: 1 cm ticks, or ½-inch ticks in inches).
  - "How to measure?" with a numbered figure (Bust, Waist, Hips, Height), plus a Submit bar.
  - Submit saves bust/waist in SharedPreferences (`gtradea_size_bust_cm`, `gtradea_size_waist_cm`) and shows "Your standard size: X". The suggestion is the larger of the bust and waist fits, and it explains which size each measurement fits. It is labelled as coming from a general chart, not the product's.
  - Submit scrolls the result into view. "See X in the size guide ›" switches to the guide tab on that size.
  - The body figure painter is now shared as `paintBodyFigure` / `dashLine` in `size_guide_sheet.dart`. Tab titles scale down rather than ellipsize.
- **Why:** the user asked for the Size recommendation tab ("built it"). No backend holds body measurements, so they stay on the device (the tab says so) and the chart is the standard one.
- **Affected:** `size_guide_sheet.dart` (header tabs, shared painters), new `size_recommendation.dart`, new `test/size_recommendation_test.dart`.
- **Impact & risk:** the guide tab is unchanged. Two bugs were found and fixed:
  - switching the unit rebuilt the ruler, which snapped 96 cm to the nearest inch and stored the change. Only a finger drag changes the value now.
  - a mid-layout notification had scheduled a build during the frame.
- **Verification:**
  - 11 new tests plus the 12 size guide tests pass. Analyze is clean. The full suite has only the 3 known `brand_system_test` failures.
  - On the Redmi: search → polo cart icon → Size guide (pills fine) → Size recommendation → swiped bust to 103 and waist to 94 → IN shows 40.6 / 37.0 in with no drift → Submit → "XL" (bust L, waist XL) scrolled into view → "See XL" opens the guide on XL (106-111). After a reinstall and reopen, the saved values and XL came back, and the full tab title shows.
- **Commit:** see git log on main, pushed to origin

## 2026-09-16 23:55 — Size Guide (button + sheet, standard chart)
- **What:** new `lib/features/product/widgets/size_guide_sheet.dart`:
  - `SizeGuideButton` -- pale rounded pill, ruler icon, "Size guide". Shown beside the **Size** heading in the options popup (replacing the earlier decoration-only `_SizeGuideTag` in `add_to_cart_sheet.dart`) and at the end of the "Choose Size: …" line in the Product Detail page's `VariantPicker` (only when the axis name contains "size").
  - `SizeGuideSheet` -- modal bottom sheet at 94% height, max width 640 (phone width on tablet/desktop), back-arrow close, swipe or tap-outside to dismiss. Layout after the Temu reference: centred "Size guide" title with underline, "Switch to" IN/CM pill toggle, "Size displayed: Standard size" with XS–3XL chips, a line-art body figure (orange chest/waist/hip rings, dashed-tie height rule) and a flat long-sleeve top (shoulder, chest, sleeve, length lines) with white orange-bordered measurement pills, an info notice, then Body chart / Product chart tabs over a horizontally scrollable `DataTable` with the chosen size's row tinted.
  - Opens on the size already chosen: `indexFor` takes the first word of a seller label ("L [50-57.5 kg]" → L, "XXXL" → 3XL), else M. Opening, browsing and closing never touch the selection.
- **Data decision (user's choice):** the live catalogue has **no size-chart data** -- checked six clothing records: sizes are bare labels, sometimes with a kg range, no chest/length/sleeve fields (sellers put charts in product photos). The user chose a **standard chart, clearly labelled**: `kStandardSizes` is a general international regular-fit tops chart (body ranges + garment flat measurements, cm; inches = cm/2.54 to one decimal), and the sheet says "General guide. These are standard measurements, not this product's -- this seller's sizes may differ. Many sellers show their own size chart in the product photos." Not drawn: the reference's Stretch scale and "UK size" dropdown (no data for either). The "Size recommendation" tab was left out by the user's choice.
- **Found and fixed:**
  - the header `Stack` had no width, shrank to the title, and put the back arrow on top of the centred title (unreliable close) -- `SizedBox(width: double.infinity)`;
  - on the Redmi the height pill ran into the sleeve pill and the length pill sat on the right edge -- garment redrawn at 78% width with hanging sleeves, length rule at 94%, height pill lowered to 80%, shoulder pill on the shoulder line;
  - a regression test now asserts no two pills overlap and all stay inside the sheet at 360/412/800 pt widths for XS, M and 3XL.
- **Affected:** new file + test; `add_to_cart_sheet.dart`, `variant_picker.dart`, `test/add_to_cart_sheet_test.dart` (tag test → opens-the-guide test).
- **Verification:** 12 size guide tests (open/close, labelled as general, opens on chosen size, chips update figures, cm↔in including ranges and table headings, both charts list every size, pill overlap/containment, phone/tablet/desktop width ≤ 640 with no exceptions, button only on size axes, selection unchanged) + options popup 11; full suite 2464 pass with only the three known `brand_system_test` colour failures; analyze clean. On the Redmi the guide opened from a t-shirt's popup matching the reference (before the pill fix). The post-fix layout was not re-checked on the device: the phone was in use (landscape, a user search) and automation was stopped; covered by the overlap test.
- **Commit:** see git log on main, pushed to origin

## 2026-09-16 22:45 — Launch order: popup banner first, then the coins
- **What:** reversed the launch sequence in `HomeScreen._maybeShowPopup`. The admin popup now shows first (extracted into `_showLaunchPopup`, which waits for it to close and returns the banner link only when the shopper followed it); the coins scene plays after it closes. With no popup, the coins play straight away, as before.
  - If the shopper **taps the banner** to follow its link, the app goes there and the coins are skipped -- a celebration in front of the page they asked for would be in the way.
  - Same gate as before: once per fresh launch, never on resume/navigation, nothing on a tour first run.
- **Why:** User: "whenever app [opens] then show popup banner then coin animation".
- **Affected:** `lib/features/home/home_screen.dart`, `test/startup_popup_test.dart`.
- **Verification:** launch group now asserts the popup is up with no coins, the coins appear only after the popup is closed and the popup does not return, and following the banner lands on `SearchResultsScreen` with no coins; startup suite 23/23; full suite 2453 pass with only the three known `brand_system_test` colour failures; analyze clean. On the Redmi a cold start still plays the coins -- **the live server has no `app_popup_banner` set**, so the popup-first half can only be seen on the device once the admin sets one; it is covered by the tests.
- **Commit:** see git log on main, pushed to origin

## 2026-09-16 22:20 — The coins scene plays on every fresh app launch
- **What:** `HomeScreen._maybeShowPopup` now opens `CoinsToWalletAnimation.show(context, value: CoinBalanceStore.instance.balance.round())` once per fresh launch, then shows the admin popup (if any) after the scene closes.
  - It reuses the popup's launch gate: waits for the saved sign-in to restore, the cold catalogue load, the tour record and the popup setting, and `PopupBannerStore.claimLaunch()` makes it once per process -- so never on resume, navigation or a rebuilt home screen.
  - A first run whose tour starts shows neither the coins nor the popup (the tour check moved ahead of both).
  - Not over a page the shopper already opened (`ModalRoute.isCurrent`).
  - **Value:** the header's own figure, so the scene and the header always agree, and no "Preview" tag. Caveat: `CoinBalanceStore.balance` falls back to `fallbackBalance` (1000) for guests and failed reads -- the scene shows that stand-in exactly as the header already does. Nothing is written or credited.
- **Switch:** `CoinsToWalletAnimation.showOnLaunch` (true in the app), set false in `test/flutter_test_config.dart` so a dialog does not open over every home test; the launch tests turn it on.
- **Why:** User: "whenever app [opens] then show this coins animation".
- **Affected:** `lib/features/home/home_screen.dart`, `lib/features/wallet/presentation/coins_to_wallet_animation.dart` (`showOnLaunch`), `test/flutter_test_config.dart`, `test/startup_popup_test.dart` (new group).
- **Verification:** 4 new tests in the launch harness -- plays on a fresh launch with the header's value and no preview, closes itself; a live admin popup waits and appears only after it; not replayed after background/resume; a tour first-run shows no coins. Startup suite 22/22; full suite 2452 pass with only the three known `brand_system_test` colour failures; analyze clean. On the Redmi, a force-stop and cold start opened the scene by itself, settled on "1,000" with no Preview tag, and a UI dump afterwards shows it closed with the home tabs back.
- **Commit:** see git log on main, pushed to origin

## 2026-09-16 21:50 — "Coins into your wallet" reward scene (frontend only)
- **What:** new self-contained `CoinsToWalletAnimation` (`lib/features/wallet/presentation/coins_to_wallet_animation.dart`). Exactly 1.0 s on one `AnimationController`; everything but the number is painted by one `_ScenePainter`, so particles, trails and coins leave nothing behind.
  - **0.0 s spark:** centre coin fades in over 180 ms, spinning on its vertical axis (face width `|cos|`), embossed star, shine; radial gold glow behind, easing to an ambient 30% by 1.0 s. Navy `#0B1B3A` → charcoal `#1C1F26` background.
  - **0.2 s cascade:** four coins pop in at 200/255/310/365 ms over 150 ms on `backOut3`, varied size (0.74–0.92) and spin phase, each throwing 6 sparkles; loose arc above the wallet.
  - **0.5 s flight:** coin i leaves at 500 + 35i ms and flies 160 ms on a parabola (`easeIn` progress), 3-ghost trail, shrinks over its last 28%, then dissolves into 5 light particles drawn down into the glass over 140 ms. Staggered, so the last lands at 0.8 s.
  - **0.8 s reveal:** the total rises from 80% scale / 60% opacity to full by 950 ms (`easeOutCubic`) with a single breath, bold rounded warm gold; the wallet border lights amber with a blurred gold glow.
  - **1.0 s settle:** a 12-sparkle ring expands and fades by 1.0 s; afterwards an idle shimmer sweeps the glass every 2.4 s.
  - Glassmorphic wallet: translucent gradient fill, flap line, soft blurred shadow. Proportional layout (`_Layout`), shown by `show()` at `min(86% width, 380)`; closes itself 1.4 s after the settle, or on a tap.
- **API-ready, no API:** the number is the `value` input -- `CoinsToWalletAnimation.show(context, value: realBalance)` later, nothing rebuilt. No store read or write, no network, no reward logic. `demoValue` = 1000.
- **Demo trigger:** long-pressing the Points half (debug/profile only, `PointsCelebration.previewEnabled`) now opens this scene with `preview: true` -- a "Preview" tag and a screen-reader label ending "No points were added." **This replaced the "+50 preview" chip demo on that gesture**; `PointsCelebration.preview` and `play` are unchanged and still tested, just not bound to a gesture.
- **Reduced motion:** no coins, flights or particles; the wallet lights and the total fades in over the second.
- **Sound:** not added. `AppSounds` exists, but a land/chime/ding sequence would need new audio assets.
- **Test switch:** `CoinsToWalletAnimation.idleShimmerEnabled = false` in `test/flutter_test_config.dart` (endless shimmer).
- **Why:** User supplied a detailed 1-second fintech-style reward animation spec, frontend only.
- **Affected:** the new file, `delivery_points_card.dart` (long-press now opens the scene), `test/flutter_test_config.dart`, new `test/coins_to_wallet_animation_test.dart`.
- **Verification:** 11 tests -- duration is exactly 1 s; no total before ~0.8 s; at 805 ms it is at ~0.6 opacity and ~0.8 scale, full and 1.0 by 1 s; `onFinished` fires at 1 s not 990 ms; any `value` is revealed (2,450); preview tag and semantics present only in preview; reduced motion still reveals; `show` self-closes after the linger and closes on tap; text has no warning underline (the dialog route is wrapped in `Material`). Test note: `Matrix4.getMaxScaleOnAxis` counts z (always 1), so scale is read from `storage[0]`. Full suite 2448 pass with only the three known `brand_system_test` colour failures; analyze clean. On the Redmi: a cascade frame (glow, five spinning coins in an arc, sparkles, glass wallet, Preview tag) and the settled frame (gold-lit wallet, "1,000", shimmer band), header still 1,000 Points.
- **Commit:** see git log on main, pushed to origin

## 2026-09-16 19:45 — Points coin animation (frontend only, API-ready)
- **What:** new `lib/features/wallet/presentation/points_celebration.dart`, wrapped around the existing gold "P" coin and figure in `_PointsHalf` (`lib/features/home/widgets/delivery_points_card.dart`). At rest nothing is added -- same coin, colours, type, spacing and layout.
  - **App-open arrival** (`AnimatedPointsCoin`): 320 ms after the coin is first built -- past `LoadingGate`'s 220 ms cross-fade, since the home content only mounts once loading ends -- it pops from 0.55 to 1.18 on `backOut3` while fading in, wobbles (decaying sine), settles on `elasticOutSoft`, with a radial gold glow blooming behind and 8 gold sparkles radiating, shrinking and fading (a `CustomPainter` that exists only while it runs). 1.1 s. Once per app process: `PointsCelebration._arrived` is static, so rebuilds, tab switches and scrolling never replay it.
  - **Balance rise** (`AnimatedPointsFigure` + the coin): coin pop/glow/sparkles, an odometer roll from previous to next on `BackOutCurve(1.2)` (slight overshoot, back to target), a landing swell with a gold colour flash, and a floating `+N` badge in the root overlay that pops on `backOut3`, drifts up 34 px and fades, then removes itself.
- **API-ready, no API:** `PointsCelebration.play(previousBalance:, newBalance:)` is the single entry the points API will call; nothing calls it today, and a fall or no change plays nothing. `PointsIncrease` carries previous/next/amount. No repository, network call, store write, reward logic or backend change was added; `CoinBalanceStore` is only read, as before.
- **Demo, isolated:** `PointsCelebration.preview(balance:)`, reachable by **long-pressing the Points half** only when `!kReleaseMode` (debug/profile). It uses `previewAmount` = 50, labels the badge "+50 preview", announces "Animation preview. No points were added." to screen readers (`excludeSemantics` so "+50" is not read), holds the example figure, then rolls back to the real balance. Nothing is stored or sent.
- **Found on the phone and fixed:**
  - the hold before rolling back was a bare `Future.delayed`, which left the figure stuck at 1,050 in tests; it is now the first 70% of the 2 s `_back` animation;
  - the arrival started inside the loading cross-fade (hence the 320 ms delay);
  - the `+N` badge in the overlay had no `Material` above it, so its text drew with Flutter's yellow double underline -- now wrapped in a transparent `Material`, with a regression test.
- **Why:** User request: frontend-only coin animation now, ready for a points API that does not exist yet, with a clearly isolated demo that never claims a real reward.
- **Affected:** the new file, `delivery_points_card.dart` (two wrappers + the long-press), new `test/points_celebration_test.dart`.
- **Known:** the card clips to its rounded corners (`Clip.antiAlias`), so the glow is partly cut and the arrival reads as subtle; balances are rounded to whole numbers for the roll.
- **Verification:** 8 tests -- arrival plays and leaves nothing behind, does not replay on rebuild, still under reduced motion; `play` counts through in-between values, overshoots past the target and settles on it; the `+N` has no preview label for a real rise; a fall or no change plays nothing; the badge has a Material ancestor and no underline; the preview is labelled (text and semantics), reaches 1,050 and returns to 1,000. Header, tour, wallet and home suites green; full suite 2437 pass with only the three known `brand_system_test` colour failures; analyze clean. On the Redmi: sparkle dots around the coin on a cold launch; long-press shows "+50 preview" with the figure overshooting to 1,052/1,053, then back to 1,000 with the badge gone.
- **Commit:** see git log on main, pushed to origin

## 2026-09-16 19:00 — Search placeholder: the whole quoted phrase turns over
- **What:** the placeholder is now shown and animated as one complete phrase in exactly the requested format -- `Search for "running shoes"`, `Search for "winter jackets"`, `Search for "gift ideas"` -- with the cursor after the closing quote. "Search for" is no longer a separate, static `Text`: `_phraseFor(keyword)` builds `'${prefix}"$keyword"'`, and that whole string slides and fades on the timings from the previous entry (2.6 s hold; out −16 px / 400 ms / easeIn; in +18 px / 450 ms / easeOut from 50 ms; width `AnimatedSize` 450 ms easeInOut; cursor 550 ms a half). The `AnimatedSize` now wraps the whole phrase, so the width follows lead and keyword together.
- **Why:** User asked for the entire phrase, quotes included, to move together, explicitly ruling out a static lead.
- **Affected:** `lib/shared/widgets/animated_search_hint.dart`, `test/animated_search_hint_test.dart`. `SearchField`, the header, search behaviour, suggestions, the clear button and the focus/pause/resume flow are unchanged.
- **Impact & risk:** phrases are ~4 characters longer with the quotes. Measured on the Redmi, `Search for "gift ideas"` spans ~323 px (≈14 px a character), so the longest, `Search for "winter jackets"`, is ≈380 px and ends clear of the mic icon; narrower phones fall back to the ellipsis. The single phrase `Text` is `Flexible` with an ellipsis, so large text sizes still cannot overflow the header (`order_tracker_test` green).
- **Verification:** hint suite 17 tests -- new: the exact quoted format with no standalone "Search for" or bare keyword drawn anywhere, both whole phrases moving mid-turn (outgoing above its line, incoming below) and the list advancing in order to "gift ideas", and the cursor's left edge within 4 px after the phrase's right edge; the timing tests re-pointed at the full phrases. Full suite 2429 pass with only the three known `brand_system_test` colour failures; analyze clean. On the Redmi: `Search for "gift ideas" |`.
- **Commit:** see git log on main, pushed to origin

## 2026-09-16 18:35 — Search placeholder timings, to the user's exact specification
- **What:** `AnimatedSearchHint` now runs these numbers exactly, and a test pins each one:
  - **Hold:** each phrase fully on screen 2.6 s (`_hold`); the next hold starts after the turn ends, so the whole 2.6 s is on the settled phrase.
  - **Out:** up 16 px, opacity 1 → 0, 400 ms, `Curves.easeIn`.
  - **In:** starts 18 px below at opacity 0, rises and fades in over 450 ms, `Curves.easeOut`, beginning 50 ms after the out.
  - **Width:** `AnimatedSize` 450 ms, `Curves.easeInOut`.
  - **Cursor:** full → 0 → full, 550 ms each half, `Curves.easeInOut`, continuous and independent of the phrases.
- **How:** `AnimatedSwitcher` has one duration and one curve per direction and no start offset, so the turn is a single 500 ms `AnimationController` and the build reads two phases off it -- out over 0–400 ms, in over 50–500 ms -- through `Transform.translate` (pixel offsets) and `Opacity`. The outgoing word is `Positioned` out of the layout, so the width is the arriving phrase's alone.
- **The cursor is a repeating fade again**, as specified (the previous entry's timer version held it still between blinks). Two things make that acceptable:
  - it sits behind its own `RepaintBoundary`, so the endless fade repaints one 1.5 pt line, not the header;
  - a static `AnimatedSearchHint.blinkEnabled` is switched **off** in `test/flutter_test_config.dart` (the `HeroBanner.autoplayEnabled` pattern), because a page with a never-ending animation never settles; the blink test turns it back on and restores it in `addTearDown`.
  - Reduced motion: fades kept, no travel, cursor lit and still.
- **Why:** User supplied the exact cycle, curves, offsets, overlap and blink timing.
- **Affected:** `lib/shared/widgets/animated_search_hint.dart`, `test/animated_search_hint_test.dart`, `test/flutter_test_config.dart`.
- **Verification:** hint suite 15 tests -- among them the 2.6 s hold (nothing new at 2.55 s, the next phrase present at 2.65 s), the outgoing word at exactly `-16 × easeIn(0.5)` and `1 − easeIn(0.5)` opacity halfway and at −16/0 at 400 ms, the incoming word still at +18/0 at 40 ms while the outgoing one has already begun, `18 × (1 − easeOut(0.5))` halfway through its own 450 ms and settled at 500 ms, `AnimatedSize` 450 ms `easeInOut`, and the cursor at 0.5 at 275 ms, 0 at 550 ms and 1 at 1.1 s. Full suite 2427 pass with only the three known `brand_system_test` colour failures; analyze clean. On the Redmi, a frame caught mid-turn shows "backpacks" arriving just below its line while the outgoing word has risen and faded to a sliver above it.
- **Commit:** see git log on main, pushed to origin

## 2026-09-16 18:15 — Search placeholder: a ticker with a blinking cursor, "Search for …"
- **What:** `AnimatedSearchHint` (`lib/shared/widgets/animated_search_hint.dart`) is rewritten, same constructor plus a `paused` flag, so the home header and the search screen both keep using it.
  - **Ticker, not typewriter.** It used to type each phrase out letter by letter and erase it. Now the example slides up and fades while the next rises from below and fades in (`AnimatedSwitcher`, 420 ms, easeOutCubic in / easeInCubic out, 2.2 s hold). The outgoing word is `Positioned` out of the layout so the two never fight for width.
  - **Blinking cursor.** A 1.5 pt rounded bar after the word, fading between 15% and 70% every 600 ms on its own `Timer.periodic` + a 280 ms `AnimatedOpacity` -- deliberately **not** a repeating `AnimationController`: that version ran a ticker forever, repainted the header every frame, and made `pumpAndSettle` time out across `widget_test.dart` (10 home tests). The old literal "|" is gone.
  - **Smooth width.** The phrase sits in `AnimatedSize`, so the cursor glides as a longer or shorter word arrives; the pill does not move.
  - **Copy.** Lead is "Search for " (both `AnimatedSearchHint.prefix` and `SearchHeader.hintText`), phrases are lower-case sentence endings starting with the requested "running shoes", "winter jackets", "gift ideas". Capped at `kSearchHintMaxLength` = 14 characters: on the phone the home pill cut "kitchen essentials" to "kitchen essenti…" with the cursor stranded after the ellipsis, so the five long ones were shortened (headphones, kitchenware, phone cases, stationery, gym gear).
  - **Large text.** The fixed lead is `Flexible` with an ellipsis. As a plain `Text` it overflowed the header by 45 px at a large accessibility text scale (`order_tracker_test` caught it).
- **`SearchField`** (`lib/features/search/widgets/search_field.dart`): focusing the empty box fades the hint out (160 ms) and passes `paused: true`, which holds the phrase it is on; unfocused and empty again, it resumes **from that phrase**, not the top of the list. A clear (X) button appears only while there is text: it clears the controller, calls `onChanged('')` so typeahead suggestions do not go stale, and keeps focus.
- **Why:** User request for an animated, ticker-style placeholder with a soft cursor, pause on focus, a clear button and resume; then "Search for …" phrasing (chosen from three options).
- **Affected:** the two files above, `lib/features/home/widgets/search_header.dart` (default lead only), `test/animated_search_hint_test.dart`.
- **Impact & risk:** Search API, suggestions, submit-on-enter, the arrow button, voice and image search untouched; the phrases never enter the input. Reduced motion: no travel -- the word fades -- and the cursor holds still.
- **Verification:** hint suite 13 tests (phrase lengths and wording, whole-word ticker with both words present mid-turn, the arriving word rising and fading in, pause without rewind, reduced motion, the blink, focus fades and pauses, clear button appears/clears/notifies/disappears, typing still reaches `onChanged`/`onSubmitted`); `widget_test` and `order_tracker_test` green. Full suite 2424 pass: the three known `brand_system_test` colour failures, and `profile_photo_sync_test` which failed only in a run slowed by a parallel APK build and passes 5/5 alone. On the Redmi: "Search for handbags|" → "home decor|" → "watches|", whole words, cursor tight to the text and caught mid-blink.
- **Commit:** see git log on main, pushed to origin

## 2026-09-16 15:30 — Options popup from the cart icon on product cards
- **What:** tapping the cart icon on a product card now opens `AddToCartSheet` (new, `lib/features/cart/presentation/add_to_cart_sheet.dart`) instead of adding the product outright. The sheet shows the picture, title and price, one group per option axis the seller actually published, a quantity stepper, and a footer that reads "Select an option" (disabled) until every axis is answered, then "Add to cart". No description, no card copy.
  - Axes come from `axesOf` in `cart_variant_catalogue.dart` -- the feed's own names ("Color", "Size") off the published SKUs. An axis whose values carry *different* pictures is drawn as swatches (colour); one whose pictures are all the same is chips (size). A pairing the seller never published, or has none of, cannot be selected (`_reachable`); the whole set must be answered before the button enables.
  - The line is built on the product page's rules: variant price beats the ladder, `tiers` only travel when they set the price, `skuId`/`specId`/`variantLabel` carried, quantity clamped to the record's MOQ and `CartStore.maxPerLine`. Added through the existing `CartStore.add`.
  - Detail comes from `ProductRepository.cachedDetail` when warm (no wait) and `detail()` otherwise (skeleton); a failed fetch says so with a retry. The button locks while adding.
  - A **Size guide** tag sits at the right of a size heading, matching the reference. It is decoration only, by request: no modal, no page, no measurement, and `ExcludeSemantics` so it is not announced as a control.
  - A `Was: …` struck price and a `% OFF` pill are drawn in the reference's style **but never appear against this gateway**: `ProductDetail.listPrice` is deliberately always null (`product_detail_content.dart:311`) because the server publishes one price per product. Nothing is invented to fill it; wiring it needs a real field from the backend.
- **Why:** User request. Every card's cart button added at `minOrder` with no variant at all, so a shirt reached the cart with no size and no colour and the choice had to be made again there.
- **Affected:** new sheet + new `test/add_to_cart_sheet_test.dart`; handlers swapped in `search_results_screen.dart`, `home_feed.dart`, `new_for_you_screen.dart`, `cart_recommendations.dart` (keeps its "added" note, now only on success) and `discover_more_section.dart`. **The Product Detail page, the cards, the cart page and the cart API are untouched.**
- **Impact & risk:** the cart button now costs a detail fetch when cold (1.5-3.6s, skeletoned); warm records open instantly. Products with no published variants behave as before, one tap further on.
- **Verification:** 10 tests -- axes offered and nothing invented, no description, the button gated on a full answer, the chosen SKU and MOQ on the line, the quantity floor, an unreachable pairing, a no-variant product, a failed fetch, the size guide tag's placement and inertness, and the off badge staying off. Analyze clean. On the Redmi: home card → popup → real line at Rs 3,719; search card → Color and Size from real SKUs → picked Apricot + S → the cart line shows both axes at Rs 497; the Size guide tag renders as the reference draws it and opens nothing when tapped.
- **Commit:** see git log on main, pushed to origin

## 2026-09-16 14:45 — ProductGrid never listened to the wishlist
- **What:** `ProductGrid` is now wrapped in a `ListenableBuilder` on `WishlistStore.instance`. It read `contains()` for each card's heart but never subscribed, so its cards kept the saved state they were first built with.
- **Why:** Two reported faults, one cause. A card saved from this grid was still drawn `saved: false`, so (a) once the card heart's fill was let go the heart fell back to an outline on a product that *was* saved, and (b) the next tap read that stale false, took the save branch, and called `toggle()` on an already-saved product -- which removed it and correctly said "Removed from Wishlist". The animation was never at fault: it does not touch the store, the overlay heart is removed on landing, and no timer calls the wishlist.
  - The rail (`product_carousel.dart`), `department_feed.dart`, `search_results_screen.dart`, `new_for_you_screen.dart` and `future_cart_screen.dart` all listen already; `recent_views_section.dart` calls `setState` itself. This grid was the only one that did not -- it also backs Free Delivery and Corporate Gifts.
- **Affected:** `lib/features/home/widgets/product_grid.dart`, `test/wishlist_flight_test.dart`.
- **Impact & risk:** the grid rebuilds when the wishlist changes, which is what every other card surface already does. No layout or card change.
- **Verification:** new regression test saves through the real store from a grid card, waits past the fill's hold, asserts the heart is still shown saved, then asserts the *next* tap is what removes it; flight suite 11/11; full suite 2399 pass with only the three pre-existing `brand_system_test` colour failures (the theme's page colour is F3F2F2, that test still expects the old ivory F2ECE6 -- unrelated to any of this work); analyze clean. On the Redmi: tapping a saved card removes it and the heart flips to outline at once; saving again leaves it filled and labelled "Saved:" nine seconds later, with no message.
- **Commit:** see git log on main, pushed to origin

## 2026-09-16 13:55 — The card heart holds its fill until the store catches up
- **What:** after the flight lands, the card heart stays filled until the card is told what really happened, instead of dropping straight back to what it was last told. A five-second timer lets it go if nothing ever comes, so a failed save cannot leave a heart that claims otherwise.
- **Why:** found on the Redmi, testing the message removal: the wishlist call, its push and the rebuild that follows take about a second longer than the animation, and in that gap the heart showed an *outline* on a product that was already saved -- which read as "the save did not take". (The store was right all along: tapping again said "Removed from Wishlist" and the count went back down.)
- **Affected:** `_SaveButton` in `lib/features/search/widgets/product_result_card.dart` (`didUpdateWidget`, a cancelled-on-dispose `Timer`), `test/wishlist_flight_test.dart`.
- **Impact & risk:** the card's own drawing only. The store still owns the saved state and takes the heart back the moment it speaks.
- **Verification:** two new tests -- the fill held through the gap, and let go when the save never lands; flight suite 10/10; analyze clean; on the Redmi the heart is still filled 2.5s after the tap, with no message and the real count on the bar.
- **Commit:** see git log on main, pushed to origin

## 2026-09-16 13:40 — No more "Added to Wishlist" message
- **What:** saving a product no longer raises the "Added to Wishlist" status message anywhere -- the card hearts (home rails and grid, department feed, search results, and every screen built on the shared card), the Product History cards, and the Save action on the product page. Removing one still says "Removed from Wishlist".
- **Why:** User request, straight after the fly-to-wishlist animation went in: the flying heart, the filled card heart and the count moving on the Saved tab already say a product was saved, so the message repeated it.
- **Affected:** `product_carousel.dart` (`toggleSavedProduct`, the shared helper), `department_feed.dart`, `search_results_screen.dart`, `recent_views_section.dart`, `product_detail_screen.dart`, `test/action_status_test.dart`. `ActionStatus.addedToWishlist` itself is kept: the cart's "Move to wishlist" is a different action, with nothing else to show for it, and still uses it.
- **Impact & risk:** Message only. The save, its chime, the store, the badge and the removal message are untouched.
- **Verification:** the two tests that asserted the message now assert its absence and the save still happening; action status, sounds, wishlist, flight and history suites 73/73; analyze clean; checked on the Redmi.
- **Commit:** see git log on main, pushed to origin

## 2026-09-16 13:20 — Fly-to-wishlist animation on the product cards
- **What:** tapping the heart on a product card now dips it to 0.85, pops it past size on `back.out(3)` and fills it pink; at the peak a copy of the heart leaves the card, arcs ~70 above the higher end (`power2.out` up, `power2.in` down), rotates 20-25 degrees, shrinks to 0.35 and fades over the last 15%; the destination heart squashes, pops, fills pink behind a glow that fades on `power1.out`, and settles on `elastic.out(1, 0.55)`; the badge pops in on `back.out(3)`; the card heart returns to its outline.
  - New `lib/shared/motion/motion_curves.dart`: `BackOutCurve(s)` and `ElasticOutCurve(amplitude, period)`, because Flutter's own `easeOutBack` (1.70158) and `elasticOut` (period 0.4) are fixed at the wrong strengths. Also names `power2Out/power2In/power1Out` so call sites read as the spec does.
  - New `lib/features/wishlist/presentation/wishlist_flight.dart`: a destination registry (`bindTarget`/`unbindTarget`) and `launch()`, which measures both ends from the live render boxes **on every tap** and flies a heart in the root overlay, removing it on landing.
  - `_SaveButton` in `product_result_card.dart` is now stateful: runs the pop, launches the flight at its peak, locks itself while its heart is away, and lets go when the sequence ends.
  - `AppBottomNav`'s Saved destination is now `_SavedTabIcon`, which registers as the flight's destination and reacts to a landing.
- **Why:** User request: a fly-to-wishlist micro-interaction on the existing product cards, spec'd in GSAP.
  - **GSAP is a JavaScript library and cannot be used in Flutter.** Its easings were reproduced natively (table above); the timelines are normalised sub-ranges of one `AnimationController`, as `animated_add_to_cart_button.dart` already does.
  - **There is no header wishlist icon in this app.** `search_header.dart` carries only orders, messages and notifications. The app's real wishlist icon *with a real count badge* is the Saved tab of `AppBottomNav`, fed by `WishlistStore.instance.count`, so that is the destination. No new header or wishlist button was created, as the request forbade.
- **Affected:** `lib/features/search/widgets/product_result_card.dart` (the shared card, so home rails and grid, department feed, search results, New for You, Future Cart, Free Delivery and Corporate Gifts all get it at once), `lib/shared/widgets/app_bottom_nav.dart`, two new files above, new `test/wishlist_flight_test.dart`.
- **Impact & risk:** No layout, spacing, type, colour, card content, header, wishlist API, wishlist page or cart change. The save is still `WishlistStore.toggle` on the tap -- the animation never performs the action, and un-saving is the plain toggle it always was. The badge is still the store's own count, not a second counter. Risks handled: overlay entries are bound to their own controller and removed on completion; a missing destination (no bottom bar on that screen) simply means no flight; the card button is locked for exactly as long as its heart is in the air, so rapid taps cannot stack flights.
- **Verification:**
  - New suite, 9 tests: one heart in the air and none left behind, an arc that rises above both ends and crosses the full width, rapid taps making one flight and one save, the card heart returning to outline, un-saving flying nothing, reduced motion still saving, the badge showing the real count, and the two curves behaving.
  - Existing wishlist / sync / sound / cart-move / New for You / Future Cart suites 99/99; analyze clean.
  - On the Redmi (profile build): mid-flight frame shows the second heart climbing away from a filled card heart with "Added to Wishlist" from the real API and the badge going 10 to 11; the landing frame shows the Saved heart filled pink inside its glow and the card heart already back to outline.
- **Commit:** see git log on main, pushed to origin

## 2026-09-16 12:35 — Product page section gaps down from 8 to 2
- **What:** the vertical seams between the product card, the guarantees strip (7-day returns / Cash on delivery / Quality checked), Highlights, Description, Specifications and Detail images are 2 instead of 8 -- first cut to 4, the measure the recommendation cards sit at, then to 2 when the user asked for a little more.
  - Four `SizedBox(height: 8)` → 2 in `product_detail_screen.dart` (lines ~1282, ~1291, ~1312, ~1400). The `SizedBox(height: 4)` at ~1268 is inside the logistics card, after its divider, and was left alone.
  - `ProductSectionPanel`'s own `EdgeInsets.only(bottom: 8)` → 2, which is the seam between Specifications and Detail images (and under the last panel). Both that panel and `LogisticsTrustCard` are used only on this page.
- **Why:** User request: reduce the empty space between those sections, using the recommendation cards' compact spacing as the reference only; then "reduce the gaps little more". The card borders already mark where a section ends, so the seam only has to keep two cards from touching.
- **Affected:** `lib/features/product/presentation/product_detail_screen.dart`, `lib/features/product/widgets/product_section_panel.dart`, `test/product_page_design_test.dart` (new test).
- **Impact & risk:** Gaps only. No section's size, padding, order, type, colour, content or behaviour changed; the outdated "eight between sections" comments were corrected.
- **Verification:**
  - New test measures the seams between the section boxes below the guarantees strip: each > 0 and ≤ 2.5.
  - Product page design, detail and MOQ suites 45/45 (and 113 across the wider product set); analyze clean.
  - On the Redmi the five sections read as one stack with even thin seams; accessibility bounds show ~13-19 device px between section boxes at dpr 3.
  - Full suite: see commit.
- **Commit:** see git log (`style(product): four-point seams between the product page sections`) on main, pushed to origin

## 2026-09-16 12:15 — Recommendation card picture flush to the card's edges
- **What:**
  - `ProductResultCard.imageFlush` (default false): the picture is drawn to the card's own top, left and right edges instead of inside `padding`, taking the card's corner radius on its top two corners. The price, title and credibility line keep the same padding, now applied to them rather than to the whole card.
  - `heightFor(..., imageFlush:)` measures the taller picture (`cardWidth`, not `cardWidth - 2*padding`) and only one padding at the foot, so the grid reserves the right extent and nothing clips.
  - `ProductGrid.imageFlush` threads it through; only the product page's "More in …" shelf passes true.
- **Why:** User request: remove the top, left and right padding around the picture in the product page's recommendation cards, and nothing else.
- **Affected:** `lib/features/search/widgets/product_result_card.dart`, `lib/features/home/widgets/product_grid.dart`, `lib/features/product/presentation/product_detail_screen.dart` (one argument), `test/product_recommendation_spacing_test.dart`.
- **Impact & risk:** The card is a shared widget -- Home, Search, Cart, Deals, Free delivery, Corporate gifts and the carousels all draw it -- so the flag is opt-in and a test pins that the default stays padded. The picture is square as before, so a flush card is about 20 dp taller.
- **Verification:**
  - New tests: flush left/right/top within the card's 1 pt border, square, inside the card; the default card still padded; gaps 4/4; no overflow at 390/800/1400 dp.
  - On the Redmi: across a row of the picture the only page-coloured pixels are the outer margins and the 12 device-px (4 dp) gap between the cards.
  - Full suite: 2387 pass; only the 3 known `brand_system_test` failures.
- **Commit:** see git log (`style(product): draw the recommendation picture to the card edges`) on main, pushed to origin

## 2026-09-16 11:45 — Product page recommendation cards sit at the Future Cart gap
- **What:**
  - New `ResultGridSpec.compact(available)`: the standard grid's columns and card padding, with `gap` and `rowGap` at 4 -- the measure `SuggestionCard.gridGap` uses on the Future Cart shelf.
  - The product page's "More in …" `ProductGrid` passes `spec: ResultGridSpec.compact`. Nothing else uses it, so every other grid keeps 10 across / 6 down.
- **Why:** User request: reduce the gaps between the recommendation cards using Future Cart's compact spacing as the reference, changing nothing else about the cards.
- **Affected:** `lib/features/search/widgets/product_result_card.dart` (new named spec), `lib/features/product/presentation/product_detail_screen.dart` (one argument), new `test/product_recommendation_spacing_test.dart`.
- **Impact & risk:**
  - Same column count and same card padding, so the card design is untouched; with narrower gaps each card gains about 3 dp of width, which is where the reclaimed space goes. The user was told.
  - Nothing else about the section, its data or the page changed.
- **Verification:**
  - New tests: the shelf's spec is 4/4, tighter than standard, same columns and padding; the drawn grid delegate carries 4/4 with no overflow at 390/800/1400 dp.
  - On the Redmi the gap between the two cards measures 12 device px at dpr 3 = 4 dp, with the page margins unchanged at both edges.
  - Full suite: 2387 pass; only the 3 known `brand_system_test` failures.
- **Commit:** see git log (`style(product): compact gaps for the recommendation grid`) on main, pushed to origin

## 2026-09-16 11:30 — No grey strip under the product page's Add to cart / Buy bar
- **What:** `_BuyBar` now puts its `SafeArea(top: false)` **inside** the white `DecoratedBox` instead of around it, so the bar's white runs to the bottom edge behind the gesture bar.
- **Why / root cause:** measured on the Redmi from a screenshot (1220×2712): white to y≈2640, then a ~57 px band of the page grey (243,242,242) with the gesture pill, because the safe-area inset sat outside the bar's own decoration. After the change the same rows read 255,255,255 to y=2711.
- **Affected:** `lib/features/product/presentation/product_detail_screen.dart` (`_BuyBar` build only). Padding, buttons, colours and behaviour are unchanged.
- **Verification:** analyze clean; product page, detail, add-to-cart, MOQ, deal and cart suites 113/113; pixels checked on the device before and after.
- **Commit:** see git log (`fix(product): run the buy bar's white to the bottom edge`) on main, pushed to origin

## 2026-09-16 10:55 — Add to cart success state was hidden by an unrelated cart error
- **Root cause, measured on the device** (temporary uncommitted `ATCPROBE` logging, profile build, real account):
  ```
  ATCPROBE done 422ms rejectedMine=false rejectedAll=0
                      syncError=category_restricted
                      serverIds=[3a4ad9e2-4bfe-…]
  ```
  - The add itself succeeded: the account returned a row id in 422 ms.
  - `_confirmSaved` also failed the add when the **whole-cart** `syncError` was set with nothing in `rejected`. This shopper's 74-line cart carries an old `category_restricted` line, so that error is always set, and every add was reported as failed: the button dropped back to "Add to cart" and an error snack was shown.
  - Not causes: the animation, its callbacks, opacity/visibility, clipping, z-order, or a rebuild resetting state. The success path was simply never reached.
- **What:**
  - `_confirmSaved` now judges only the keys being added: refused (`rejected`) → false; otherwise every line must carry a `serverId`. The blanket `syncError` check is gone -- a line the server did not take has no id, which answers the question by itself.
  - `AnimatedAddToCartButton.holdSuccess` 2.5 s → 4 s, so the success state is easier to see.
- **Why:** User reported the animation playing but "Added to Cart" never appearing.
- **Affected:** `lib/features/product/presentation/product_detail_screen.dart` (`_confirmSaved`), `lib/features/product/widgets/animated_add_to_cart_button.dart` (hold only), `test/animated_add_to_cart_test.dart` (new test: an error about another line does not block this add).
- **Impact & risk:** Add-to-cart success is now judged per line. A failed save still shows no success (no id) and returns to rest with the error.
- **Verification:**
  - analyze clean; add-to-cart, cart, detail and MOQ suites 86/86.
  - On the Redmi (profile build, signed in, real backend): "✓ Added to cart" on the pale-green fill is clearly visible after the drop, and the cart badge rose by the minimum order (10).
  - That check added 10 × "Manufacturer Supplies Power Cords…" to the real cart (and an earlier probe run added another 10); the user was told.
  - Full suite: 2383 pass; only the 3 known `brand_system_test` failures.
- **Commit:** see git log (`fix(product): confirm the added line itself, not the whole cart sync`) on main, pushed to origin

## 2026-09-16 02:35 — The "Added to Cart" confirmation card removed from the app
- **What:** `ActionStatus.addedToCart` and its private parts (`_AddedMark`, `_InCartChip`, `_ViewCartButton`) are gone, with the call removed from all seven screens that raised it: Product Detail, Home feed, New for You, Search results, Deals, Future Cart, Product History.
  - Adds themselves are untouched: the same `CartStore.add` with the same line, quantity and rules.
  - Counts that existed only to feed the card, and the imports that went with them, were removed too.
- **Kept:** `ActionStatus.addedToCartLabel` and `ActionStatus.show` (the Wishlist screen's plain "Added to Cart · N in cart" line uses both), the product page's grid snack ("Added N pieces across M options"), and the animated Add to cart button, which is now the product page's own confirmation.
- **Why:** User request, pointing at the card: remove it from the app and delete its test file, and nothing else.
- **Affected:** `lib/core/ui/action_status.dart`, the seven screens above; deleted `test/added_to_cart_card_test.dart`; `test/cart_test.dart` lost the one expectation that the card appeared.
- **Impact & risk:** No confirmation popup after an add anywhere. The cart badge, the cart itself and the product page's Added state still say so.
- **Verification:** analyze clean; full suite 2382 pass with only the 3 known `brand_system_test` failures.
- **Commit:** see git log (`refactor(ui): remove the Added to Cart confirmation card`) on main, pushed to origin

## 2026-09-16 02:05 — Product Detail: animated Add to cart (shirt drop, cart spring, confirmed success)
- **What:**
  - New `lib/features/product/widgets/animated_add_to_cart_button.dart`, used **only** by the Product Detail bottom bar (`_BuyBar`). Every other add-to-cart in the app is unchanged.
  - **At rest:** the same outlined pill as before (existing `add_shopping_cart` icon, existing label "Add to cart", theme style), with nothing animating.
  - **On tap** (one 1000 ms controller, transforms and opacity only, inside a `RepaintBoundary`):
    - 0–18%: a painted folded shirt fades in above the icon and lifts; it stretches taller and narrower; the button presses to 96%.
    - 18–38%: ease-in drop, getting longer and narrower.
    - 38–46%: impact flattens the shirt, then it shrinks and fades.
    - 38–62%: a faint primary ring expands and fades.
    - 38–100%: the cart squashes, springs past its size, then a decaying wobble settles.
  - **Success** (360 ms): the cart and label fade out, then a ✓ with "Added to cart" scales in with `easeOutBack` over a pale `successGreen` (14%) fill with a green edge. It holds for 2.5 s, then returns to rest. No spinner.
  - **Reduced motion** (`disableAnimations`): no shirt, ring, press or wobble; the success state appears without animation.
- **Real cart flow:**
  - `_addToCart` now returns `Future<bool>`. It runs the same validation and the same `CartStore.add` (single line or grid picks via the new `_putPickedInCart`; Buy Now is unchanged).
  - It then calls `_confirmSaved`, which uses the existing store: it waits for any in-flight sync, runs `syncNow()`, and succeeds only if none of these keys are in `rejected`, the sync didn't fail as a whole, and every line has a `serverId`.
  - A guest cart is on-device, so the add itself is the confirmation.
  - The success button only shows on true. On false the button returns to rest and the refusal or sync error message is shown. The line stays in the cart, as the existing cart system does on a failed save, and it retries.
  - Taps are ignored while busy or showing success (no duplicate requests). Stock, MOQ, variant and quantity rules are unchanged.
- **Why:** User request for this exact interaction, Product Detail only, tied to the real backend add, no fake success, reduced-motion and accessibility support.
- **Affected:**
  - new widget file; `lib/features/product/presentation/product_detail_screen.dart` (add flow, `_confirmSaved`, buy bar button only)
  - new `test/animated_add_to_cart_test.dart`:
    - rest
    - success waits for confirmation even after the drop
    - refused → rest
    - no duplicate taps
    - reduced motion
    - ≥ 44 dp target
    - signed-in success sets `serverId`, variant and MOQ quantity
    - failed POST never says Added
    - guest
- **Impact & risk:**
  - A signed-in Add to cart now triggers an immediate sync instead of the 600 ms debounce (same reconcile).
  - Label casing kept as the existing "Add to cart" / "Added to cart" (the spec wrote "Add to Cart").
- **Verification:**
  - analyze clean. New tests plus cart, MOQ, deal, detail and reorder: 105/105.
  - On the Redmi (profile build, signed in, real backend), rapid screenshots showed the shirt above the cart right after the tap, then the pale-green "✓ Added to cart". (At the time of that run the old confirmation card still showed too; the next entry removes it.)
  - This added 5 × "Outdoor wholesale laser 98K infrared slingshot" to the user's real cart; the user was told.
  - Full suite: 2382 pass; only the 3 known `brand_system_test` failures (run after the confirmation card was removed).
- **Commit:** see git log (`feat(product): animated Add to cart on Product Detail, success only after the cart confirms`) on main, pushed to origin

## 2026-09-16 01:40 — Product page scrolling: gallery no longer repaints the card or resizes during scroll
- **Investigation:**
  - Measured with a **profile** build on the Redmi (120 Hz, 8.3 ms budget), using the existing `FrameProbe` plus temporary uncommitted logging.
  - **Note:** every APK installed in this session had been a *debug* build, which is inherently janky in Flutter. The user's experience was partly that.
  - **Idle at the top** while the gallery auto-rotated: continuous 120 Hz frames, **15–42% over budget**, build ~2–3 ms and raster ~5–6 ms per frame. The 3 px countdown `LinearProgressIndicator` had no `RepaintBoundary`, so each tick repainted the whole product card, photo included.
  - **Idle mid-page:** 0 frames. Scrolling mid-page was 0–1% over budget, so the rest of the page was fine.
  - **Gallery resizes itself:** the box follows each photo's aspect ratio (`AspectRatio(_ratio)`) and auto-rotates every 2.5 s. A slide change resizes the card, and all content below shifts, including while the user scrolls. It also restarts rotation when rebuilt on scrolling back up. This is the jump/vibrate cause.
  - **Detail images panel** (7 images) built them all at once when opened: one short over-budget stretch (10%), then 0–1%. Minor, so not changed.
  - No scroll-driven API calls. Not applicable: DOM or CSS (Flutter app).
- **What** (`lib/features/product/widgets/product_gallery.dart` only):
  - **Repaint:** `RepaintBoundary` around the countdown bar.
  - **Pause while scrolling:** auto-rotation pauses while the page's own vertical `ScrollPosition.isScrollingNotifier` is true, or while the gallery's top edge is scrolled off screen.
    - It uses `RenderAbstractViewport.getOffsetToReveal`, evaluated only at scroll start/end, not per pixel.
    - It resumes when the page is still with the top edge in view. Top edge rather than the whole gallery, so tall galleries on tablet or desktop still rotate.
  - Manual swipe, thumbnails, video tab, tap-to-view and the design are unchanged.
- **Why:** User reported product page scrolling that stutters, vibrates or jumps, and sometimes freezes. They asked for the real root cause and a minimal fix.
- **Affected:**
  - `lib/features/product/widgets/product_gallery.dart`
  - new `test/product_gallery_scroll_test.dart`:
    - the bar has its own repaint boundary
    - no slide change during a 5 s drag
    - scrolled past the top edge → stays put; back at the top → resumes
    - idle at the top still rotates
- **Impact & risk:**
  - The gallery rotates only while its top is on screen and the page is still.
  - The `_measure()` full-size decode for aspect ratio is left as is (800×800 on the tested listing).
- **Verification:**
  - Profile build, same steps before and after: idle at the top while rotating went from 15–42% to **5–17%** over budget, build p50 3.0 → 1.1 ms. Mid-page stays 0–1%.
  - The remaining over-budget frames at the top are the slide animation's photo raster (~4–5 ms on this device).
  - Product page suites (gallery scroll, video, images, detail, design, deal, MOQ) 93/93; analyze clean.
  - The profile build (not debug) is left installed on the phone.
  - Not run: tablet and desktop on physical devices.
  - Full suite: 2377 pass plus the 3 known `brand_system_test` failures, and 1 real failure found by it: `cart_test` "quantity chosen on the page". The page-scroll notifier fired mid-layout and stopped the countdown inside a frame ("Build scheduled during frame"). Fixed by deferring the handler to a post-frame callback when the scheduler is mid-frame; `cart_test` plus the gallery, video, detail and images suites now pass (115).
- **Commit:** see git log (`perf(product): stop gallery repaint and rotation from fighting page scroll`) on main, pushed to origin

## 2026-09-16 00:55 — Discover more products: brand-blue text, compact cards, fetched early and once
- **Measured root cause of slow rendering** (Redmi, temporary uncommitted logging):
  - The `/search/products?sort=sales` request itself answers in ~200 ms.
  - **Late start:** the section sits at the foot of the lazily built history `ListView`, so its `initState` fetch only started when the shopper scrolled down (7.6 s after opening in the run).
  - **Refetch:** scrolling away and back disposed and rebuilt it, fetching again (a duplicate request).
  - Images already went through `ArtworkPanel` / `AppImages`, so they were not the cause.
- **What:**
  - **Shared fetch:** `DiscoverMoreSection.prefetch()` is a static in-memory result with a 5-minute TTL, a single in-flight future and the same query (sort by sales, 12 → first 8 priced).
    - `ProductHistoryScreen.initState` calls it unawaited, with errors swallowed, so the fetch starts as the page opens without blocking the history.
    - The section's state initialises from `cached`: if the result is in, it draws on the first frame with no skeleton or request. Otherwise it shows `ProductCarouselSkeleton` at the compact width until the shared future answers.
    - An error still hides the shelf, as before.
  - **Colours:** the heading, See all and category-chip text use `colorScheme.primary` (brand blue, the user's choice), and the chip tint is primary at 8%. The explore icon stays orange (icons unchanged), and the subtitle is unchanged.
  - **Compact cards:** `ProductCarousel` / `ProductCarouselSkeleton` gained an optional `width` (default `cardWidth` 190, so the home page and quote screen are unchanged). Discover uses `DiscoverMoreSection.cardWidth = 150`, so the square picture and the card height (`heightFor(width:)`) shrink proportionally with the same layout.
- **Why:** User request: change heading, See all and category colours; smaller images and cards; fix slow rendering with real data, no duplicate requests, no page blocking.
- **Affected:**
  - `lib/features/account/presentation/discover_more_section.dart`
  - `lib/features/home/widgets/product_carousel.dart` (optional width only)
  - `lib/features/account/presentation/product_history_screen.dart` (one prefetch line)
  - `test/discover_more_test.dart`, new tests:
    - colours
    - the card is smaller than the storefront card
    - one request across rebuilds
    - a prefetched shelf draws on the first frame
    - compact skeleton while loading
    - 360/800/1400 dp with no overflow
- **Impact & risk:**
  - The trending shelf can be up to 5 minutes old within a session.
  - The Product History screen makes this one request on open even if the shopper never scrolls down (~200 ms, tiny payload).
- **Verification:**
  - analyze clean. Discover tests 12/12; history, recent views and quote tests 84/84.
  - On the Redmi:
    - one fetch at page open
    - the section built with data ready (no skeleton) when scrolled to
    - no second fetch after scrolling away and back
    - blue heading, See all and chips, and smaller cards (about 2.4 per screen width vs 2)
  - Not run: tablet and desktop on physical devices (widget tests cover widths).
  - Full suite: 2380 pass; only the 3 known `brand_system_test` failures.
- **Commit:** see git log (`perf(history): compact brand-blue Discover more shelf, fetched early and once`) on main, pushed to origin

## 2026-09-16 00:25 — Product History Load More button made clearly visible
- **What:** The Load More `OutlinedButton` now uses the account card's Sign Up treatment:
  - `foregroundColor` and `side` = `colorScheme.primary`, `backgroundColor` = `colorScheme.surface`, w600 label
  - while a batch loads (disabled), foreground stays primary and fill stays surface, beside the spinner
  - the theme's 44 dp height, control radius and typography are kept
- **Why / root cause:**
  - The user reported the button and its text as not visible.
  - It used the theme's default outlined style: a transparent fill with the pale `border` hairline, on the grey page, so it read as a faint box.
  - While loading, Material's default disabled colours (38%) made it almost invisible.
  - A first attempt at 75% primary for the loading label measured 3.3:1, so full primary is used instead.
- **Affected:** `lib/features/account/presentation/product_history_screen.dart` (button style only); `test/product_history_older_test.dart` (new contrast test).
- **Impact & risk:** Visual only, for this button. Behaviour (append, spinner, no double tap, hide at end) is unchanged. Dark theme follows `colorScheme`.
- **Verification:**
  - New test: opaque fill; label ≥ 4.5:1 against the fill and edge ≥ 3:1 against the page, both idle and loading.
  - History suites 47/47.
  - On the Redmi: blue-edged white button with a readable blue "Load More" label.
  - Full suite: 2372 pass; only the 3 known `brand_system_test` failures.
- **Commit:** see git log (`fix(history): make Load More clearly visible`) on main, pushed to origin

## 2026-09-16 00:10 — Product History cards appear complete (image + description + price together)
- **Root cause, investigated:**
  - **Different data paths:** the history row (`/product-views`) carries only `product_data.name` and `image_url` (measured). The description, ✓ highlight, department chip and live price exist only in the per-product `/api/1688/product` record.
  - The card drew from the row at once and filled in the record's fields later, so the image came first and the text second.
  - **Queue:** the previous task's 3-at-a-time detail queue made lower visible cards fill in later still.
  - **Redraws:** each record also caused its own `setState`.
  - Not causes: slow list query (~200 ms), data conversion, Suspense (Flutter app).
- **Found on device during the fix:** showing a card on its record alone reversed the problem, with text and price beside an empty image tile. So the picture is now part of "complete" too.
- **What** (`recent_views_section.dart`; plus `ProductRepository.cachedDetail`):
  - A card whose record hasn't settled is drawn as the whole-card `RecentViewsSkeleton(rows: 1)`, same size. It switches in one step to the full card when the record (or its failure) **and** the picture are in.
  - **Parallel:**
    - the picture download (`warmImage` → `precacheImage` on the exact provider the tile uses, `_ViewRow.imageOf`) starts at the same moment as the record request
    - all records in the batch start at once, with the queue removed
    - each product is requested once (`_asked`)
  - **Fallbacks:** a failed record draws the card from history data; a failed image doesn't block. A slow image may hold a card at most 4 s (`imageGrace`) after its record, never forever.
  - A record in the 5-minute product cache is used without a request.
  - Record arrivals are grouped into one rebuild per microtask burst.
  - Card design, sizes, chip, padding, the duplicate-spec fix, Load More and error/Retry are unchanged.
- **Backend limitation, reported:**
  - The backend source isn't on this machine, and `/product-views` can't be made to return price/description from the app.
  - A stored price would also go stale against authoritative server pricing.
  - To remove the per-product request entirely, the backend should join the current display price, category and a description summary into `/product-views` rows.
- **Why:** User request: description and price must appear with the image as one complete card, fix the real data path, no fake data or delays.
- **Affected:**
  - `lib/features/account/presentation/recent_views_section.dart`
  - `lib/features/product/data/product_repository.dart` (`cachedDetail`, read-only)
  - `test/flutter_test_config.dart` (`RecentViewsSection.warmImage` no-op, like `AppImages.providerOverride`)
  - `test/recent_views_section_test.dart`, new tests:
    - slow record → only a skeleton, then all fields at once
    - a cached record draws with no request
    - the batch starts all records once each
    - the card waits for its picture, started alongside the record
  - `test/product_history_older_test.dart` (timing in one test)
- **Verification:**
  - analyze clean; product history suites 46/46.
  - On the Redmi, rapid screenshots showed whole-card skeletons, then complete cards (image, name, description, ✓ line, chip, price, Buy Now) in one step, with no half-filled card in between.
  - Not run: tablet and desktop on physical devices (none available). Phone, tablet and desktop widths are covered by widget tests.
  - Full suite: 2371 pass; only the 3 known `brand_system_test` failures.
- **Commit:** see git log (`perf(history): render Product History cards whole, fetching record and image together`) on main, pushed to origin

## 2026-09-15 23:45 — Product History: faster loading, full-screen card skeleton, append-only Load More
- **Measured root cause** (live gateway, Redmi, temporary uncommitted logging):
  - `/product-views?limit=40` took ~210 ms, so the list itself was not slow.
  - The Recently Viewed tab also awaited the orders refresh (+~190 ms) though it doesn't show orders.
  - **The slow part:** every card fetched its full product record from `/api/1688/product` for the grey description line and ✓ highlight. That was 40 requests fired at once, **1.5–3.6 s and up to 208 KB each**.
- **Backend facts, measured:**
  - `/product-views` ignores `offset`, `page`, `cursor` and `before`, and returns a bare array with no `has_more` or total.
  - It holds or returns at most 50 rows; `limit` > 100 silently falls back to 20.
  - The backend source isn't on this machine, so there's no DB index or query change.
  - **Backend follow-up needed for true pagination:** accept `offset` or `cursor`, return `has_more` (or `next_cursor`), and index `(user_id, viewed_at DESC)`.
- **What (app):**
  - **First load:**
    - batch of 10 (`pageSize`), fetched in parallel with the hidden-rows read
    - the orders refresh runs alongside, for the Purchased tab only (own spinner)
    - pull-to-refresh restarts at 10
  - **Product details:**
    - requested only for loaded rows, through a queue: 3 at a time, top card first
    - each product asked once (`_asked` set, plus the `ProductRepository` 5-minute cache and in-flight sharing)
    - 10 requests on open instead of 40
  - **Images:** `AppImages.of` (resized to the tile, disk-cached) instead of full-size `Image.network`.
  - **Load More:**
    - asks for held + 10, since the route has no offset, and appends only rows whose key isn't already held
    - existing cards are never replaced, and only the new rows fetch details
    - the button keeps its place, shows a spinner and is disabled while loading (no double request)
    - it hides when the server's `has_more` (read if ever sent) is false, when the batch came back short of what was asked, or when nothing new came back
    - a failure keeps the cards and shows "Try again"
    - `limit` is clamped to the route's 100 max
  - **Skeleton:**
    - `RecentViewsSkeleton.rowsFor(height)` fills the visible area from the top, up to 16 cards
    - it uses the real card inset `fromLTRB(4,8,8,8)` and extent, fades into the cards (220 ms), and keeps its existing shimmer
    - the error and Retry state is unchanged
  - Card design and the earlier chip, padding and duplicate-spec fixes are unchanged.
- **Why:** User request: make Product History actually faster, not just look faster; add a card skeleton and a real Load More without duplicates or reloads.
- **Affected:**
  - `lib/features/account/data/product_views_repository.dart`: `page()`, `ProductViewsPage`, `maxLimit`; `list()` kept
  - `lib/features/account/presentation/product_history_screen.dart`
  - `lib/features/account/presentation/recent_views_section.dart`
  - `test/product_history_older_test.dart`, rewritten for the batch of 10 and append behaviour, with new tests for:
    - no duplicate detail requests
    - the Purchased tab not blocking the Viewed tab
    - the skeleton filling the screen
    - `has_more`
    - phone, tablet and desktop widths
- **Impact & risk:**
  - Only 10 cards are shown until Load More.
  - Descriptions fill in card by card, 3 at a time; slots are fixed height, so there's no layout jump.
  - With a 50-row server history, the final Load More returns nothing new and the button then hides.
- **Verification:**
  - analyze clean; product history, older-history and recent views suites 42/42.
  - On the Redmi:
    - the skeleton shows immediately
    - the first batch arrives in 318 ms
    - all visible cards were complete by about 1.5 s (with 10 detail requests, instead of seconds of 40 parallel 1.5–3.6 s requests)
    - Load More shows a spinner and disabled button, cards stay, 10 rows are appended in place, and only 10 new detail requests go out
  - Detail timings in the after-run were partly warmed by the server's cache from the earlier probe, so the speedup comes from the request count (40 → 10 per batch), not those timings.
  - Full suite: 2367 pass; only the 3 known `brand_system_test` failures.
- **Commit:** see git log (`perf(history): batch Product History, throttle detail fetches, append-only Load More`) on main, pushed to origin

## 2026-09-15 23:10 — Product History cards: smaller red chip, image closer to edge, no duplicate spec
- **What** (Recently Viewed cards, `_ViewRow` in `recent_views_section.dart`):
  - **Red-orange department chip** (`commerceOrange`): font 10.5 → 9.5, padding h8/v2 → h6/v1, one line with ellipsis. It stays on the price row instead of wrapping to two lines and making the card taller.
  - **Image:** the card's inner padding went from `all(8)` to `fromLTRB(4, 8, 8, 8)`, so the photo sits closer to the left edge.
  - **Duplicate description:**
    - Root cause: `_blurb` falls back to the first spec when the listing has no prose, and `_highlights` also took `specs.first`, so "Brand: Pulse treasure" printed twice.
    - `_highlights` now skips the spec the blurb already shows and uses the next one, or none.
- **Why:** User request: reduce the red text size and keep it inline, reduce the left padding around the image, fix the description showing the same info twice. UI only.
- **Affected:**
  - `lib/features/account/presentation/recent_views_section.dart`
  - `test/recent_views_section_test.dart`:
    - the old test expected the second spec never to show; it now expects each spec exactly once
    - new tests: one spec prints once with no highlight line; the chip stays one line
- **Impact & risk:**
  - Visual only on these cards. Data (`/product-views` plus the product detail API), image, title, price, Buy Now, heart and taps are unchanged.
  - Long department names now truncate with "…".
- **Verification:**
  - analyze clean; recent views and product history suites 35/35.
  - On the Redmi the chips are one line ("Display ra…", "Electric c…"), the images are closer to the left edge, and no card repeats a line (e.g. "Brand: Pulse treasure" then "Model: 60v20ah…").
- **Commit:** see git log (`style(history): compact department chip, tighter image inset, no repeated spec`) on main, pushed to origin

## 2026-09-15 22:05 — Popup reliably shows on every fresh launch (root cause fixed)
- **What:**
  - The popup's once-per-launch decision now also waits for the saved sign-in to be restored (`AuthStore.isLoaded`), and `AuthStore` joined the popup triggers.
  - `TourStore` unloads synchronously when the restored account arrives, so the decision then waits for that account's tour record.
- **Root cause:**
  - At cold start the keystore (secure storage) answers after the catalogue, the popup setting and the tour's guest read. The device log confirmed it: the decision ran with `auth=false`.
  - The tour was still reading the guest key, while a signed-in shopper's finished tour lives under the account key. The popup read "tour pending", skipped, and burned the launch, so it failed on every launch.
  - The earlier persisted `gtradea_popup_seen` list (removed in the 19:45 entry) was the other historic "only once" cause.
- **Launch detection:**
  - `PopupBannerStore.launchHandled` lives with the Flutter engine / Dart isolate. Force-stop, back-out and swipe-away all start a new engine, so the flag is fresh. Resume and navigation keep the same engine.
  - The trigger is event-driven (no timer).
  - No design change.
- **Why:** User reported the popup not appearing on repeated opens and asked to fix the root cause so it shows on every fresh launch, once per session.
- **Affected:** `lib/features/home/home_screen.dart` (popup trigger and readiness only), `lib/features/promo/data/popup_banner_store.dart` (doc only), `test/startup_popup_test.dart`.
- **Impact & risk:**
  - The popup may appear slightly later on cold start, after the keystore read.
  - If the keystore never answers, `AuthStore.load` still completes: its read errors resolve to signed out.
- **Verification:**
  - analyze clean. `startup_popup_test` 18/18 plus `tour_overlay_test`.
  - New regression test with a keystore held back until released: no decision while the sign-in is unknown, then the popup shows for a signed-in user with a finished tour. It fails without the fix, as checked.
  - On the Redmi (temporary uncommitted `--dart-define` preview build; the server setting is still null):
    - fresh launch → popup
    - close → Account and back → no popup
    - Home and reopen → no popup
    - force-stop and open → popup
    - back-out and open → popup
  - The clean build was reinstalled afterwards.
  - Full suite: 2358 pass; only the 3 known `brand_system_test` failures.
- **Commit:** see git log (`fix(promo): wait for sign-in restore before deciding the startup popup`) on main, pushed to origin

## 2026-09-15 20:05 — Popup card centred on screen
- **What:** The popup card itself now sits exactly in the centre. Before, the frame only added the close button's 18 dp overhang on the right and top, so the card sat about 9 dp left of and below centre. The frame now adds the overhang on all sides; the close button position and card size are unchanged.
- **Why:** User request: "add center of the screen". The user also reported no popup after opening the app several times. Cause: the live `app_popup_banner` setting is still null. The user chose to set the banner themselves in the admin panel.
- **Affected:** `lib/features/promo/presentation/startup_popup_banner.dart` (frame and card offset), `test/startup_popup_test.dart` (centre assertions).
- **Impact & risk:** Popup layout only.
- **Verification:** `startup_popup_test` 17/17, now including a check that the card centre equals the screen centre at 360/800/1400 dp.
- **Commit:** b13ea37 (`fix(promo): centre the popup card on screen`) on main, pushed to origin; log entry in a follow-up commit.

## 2026-09-15 19:45 — Popup shows on every fresh app launch
- **What:**
  - The startup popup now shows on every cold launch, meaning the app was fully closed and opened again, after the loading screen finishes.
  - It does not show again when returning from the background, moving between pages, or when the home screen is rebuilt in the same run.
  - Replaced the saved "seen campaign ids" list (`gtradea_popup_seen`, no longer read or written) with an in-memory `PopupBannerStore.launchHandled` / `claimLaunch()`. It lives as long as the app process, and a fresh launch is a new process.
  - `HomeScreen` checks the store's flag instead of its own field.
  - The trigger is still event-driven with no timer: loader done, tour loaded, setting loaded.
  - The tour-first rule is kept.
  - If Android kills the app in the background, reopening it is a fresh launch and the popup shows.
- **Why:** User request: show on fresh launch only, not on navigation or resume; trigger from real lifecycle/startup state, not a timer. This supersedes the earlier "once per banner until closed" choice.
- **Affected:** `lib/features/promo/data/popup_banner_store.dart`, `lib/features/home/home_screen.dart` (popup trigger only), `test/startup_popup_test.dart`.
- **Impact & risk:** People now see a live campaign on each cold start even after closing it. There's no other behaviour change.
- **Verification:**
  - analyze clean; `startup_popup_test` 17/17 and `tour_overlay_test` pass.
  - New tests: every fresh launch shows it after a close; background → resume doesn't show it; push/pop doesn't show it; home rebuilt in the same run doesn't show it.
  - On the Redmi, with a temporary uncommitted `--dart-define` preview build (server setting still null):
    - cold start → popup
    - close, Home key, reopen → no popup
    - Account and back → no popup
    - force-stop and launch → popup again
- **Commit:** see git log (`feat(promo): show startup popup on every fresh launch`) on main, pushed to origin

## 2026-09-15 19:15 — Startup promo popup banner (admin-managed site setting)
- **What:**
  - After the existing loading screen finishes, the home screen can open a promo popup: dimmed backdrop, portrait artwork card (radius 12), and a round white ✕ on its top-right corner.
  - Tapping the artwork follows `button_link`. Like the hero banners, only `/search?q=` routes are followed (to SearchResultsScreen); any other link just closes the popup.
  - The content comes only from the backend setting `GET /site-settings/app_popup_banner`, with nothing hardcoded. Null, invalid, inactive, expired, a failed request or artwork that won't load all mean no popup, silently.
  - The artwork is decoded before the card opens, so it never shows as an empty box.
  - Closing or following a campaign stores its `id` in SharedPreferences (`gtradea_popup_seen`), so each campaign shows once per device. A new `id` shows again.
  - A launch that opens the guided tour skips the popup; it shows on the next launch.
  - The popup is decided at most once per launch and won't open over a page the shopper has already navigated to.
  - The card is 84% of the width, capped at 420 dp and at 78% of the height, and stays portrait 9:16. It's phone-sized on tablet and desktop.
- **Backend contract** (the admin must seed this; the server currently returns `setting_value: null`):
  `{"id":"campaign-id","image_url":"https://…portrait.png","button_link":"/search?q=sale","alt_text":"…","start_date":"YYYY-MM-DD","end_date":"YYYY-MM-DD","is_active":true}`.
  - `end_date` as a bare date runs through the end of that day.
  - The value may be JSON or a JSON string.
- **Why:** User request: show a banner matching the reference right after startup. User's choices: new admin-managed site setting; once per banner until closed; tour first, popup on next launch.
- **Affected:**
  - new `lib/features/promo/data/popup_banner.dart`, `popup_banner_store.dart`, `lib/features/promo/presentation/startup_popup_banner.dart`
  - `lib/features/home/home_screen.dart`: one-shot trigger in initState/dispose, nothing else changed
  - new `test/startup_popup_test.dart`
- **Impact & risk:**
  - Additive; there's one extra public request at startup.
  - Nothing is visible until the backend sets the key.
  - Test seam `StartupPopupBanner.decodeOverride`: a decode inside the widget-test fake clock never finishes.
- **Verification:**
  - `flutter analyze` clean.
  - `test/startup_popup_test.dart` 15/15: null, live, close persists, new id, inactive/expired, tour pending, image failure, server 500, CTA link, and 360/800/1400 dp with no overflow and the close button on screen.
  - Full suite: 2355 pass; only the 3 known pre-existing `brand_system_test` failures.
  - On the Redmi, startup is unchanged and there's no popup while the setting is null. The popup itself hasn't been seen on the device yet because no real campaign data exists.
- **Commit:** see git log (`feat(promo): startup popup banner from site settings`) on main, pushed to origin

## 2026-09-15 17:25 — Account card runs to the bottom; greeting padding 11
- **What:**
  - The page list's bottom padding went from 32 to 0, and `_AccountCard`'s bottom padding from 12 to `32 + MediaQuery.viewPaddingOf(context).bottom`, so the white card continues below Sign out to the foot of the screen, behind the navigation bar, and no grey page shows underneath.
  - Also included: the user's own edit of `_ProfileCard` padding from `EdgeInsets.all(16)` to `EdgeInsets.all(11)`.
- **Why:** User request: add white card below the Sign out button and do not show the grey page. The padding edit was made by the user.
- **Affected:** `lib/features/account/presentation/account_screen.dart` (ListView padding, `_AccountCard` padding, `_ProfileCard` padding).
- **Impact & risk:** Account screen spacing only. Note: `all(11)` also brings the avatar and Switch 5 dp closer to the side edges than the rest of the page (which aligns at 16). `fromLTRB(16, 11, 16, 11)` would keep that alignment; the user was told and it was left as they set it.
- **Verification:** analyze clean; auth, account and multi-account suites 63/63. On the Redmi the card is white from the greeting to the bottom edge, with no grey below Sign out.
- **Commit:** see `git log` — `style(account): run the account card to the bottom of the page`, pushed to origin `main`.

## 2026-09-15 17:05 — Greeting block without its own card
- **What:** `_ProfileCard` (avatar, "Hello, name", email, Switch) no longer draws its own tinted wash, border or shadow; it sits directly on the account card. Its 16 dp padding and all content are unchanged. The guest card (signed out) keeps its card.
- **Why:** User request: remove the card from the greeting, email and Switch, as done for the other sections, nothing else.
- **Affected:** `lib/features/account/presentation/account_screen.dart` (`_ProfileCard` decoration only). `test/account_cards_test.dart`: lifted surfaces 2 -> 1 (only the account card).
- **Impact & risk:** Visual only, for the greeting. Name, email, avatar, Switch and routes are unchanged.
- **Verification:** analyze clean; auth, account, login activity and profile photo sync suites 83/83. On the Redmi the greeting sits on the plain account card.
- **Commit:** see `git log` — `style(account): drop the greeting block's own card`, pushed to origin `main`.

## 2026-09-15 16:58 — Recently viewed rail without its own card
- **What:** `_RecentlyViewedRail` no longer draws its own surface, edge lines or shadow; its products sit directly on the account card, like Account settings and Help and information. Padding, height, horizontal scroll and the edge clip are kept, and tile images, names, prices and taps are unchanged.
- **Why:** User request: remove the card from the recently viewed products, as done for the settings and help sections, nothing else.
- **Affected:** `lib/features/account/presentation/account_screen.dart` (rail container decoration only).
- **Impact & risk:** Visual only, for the rail. `RecentlyViewedStore` and the other recent-views uses are untouched.
- **Verification:** analyze clean; auth, account and recent views suites 87/87. On the Redmi the products sit on the account card with no rail edge.
- **Commit:** see `git log` — `style(account): drop the recently viewed rail's own card`, pushed to origin `main`.

## 2026-09-15 16:50 — Help and information rows without their own card
- **What:** Help and information passes `card: false` to `_RowGroup`, like Account settings. Its rows sit directly on the account card with no edge lines or shadow of their own. Rows, icons, text, dividers and spacing are unchanged.
- **Why:** User request: remove the card from Help and information as was done for Account settings, nothing else.
- **Affected:** `lib/features/account/presentation/account_screen.dart`. `test/account_cards_test.dart`: lifted surfaces 3 -> 2 (outer card, Account).
- **Impact & risk:** Visual only, for Help and information. Routes and behaviour are unchanged.
- **Verification:** analyze clean; account suites 101/101. On the Redmi Help and information sits on the account card, above Sign out.
- **Commit:** see `git log` — `style(account): drop the help and information rows' own card`, pushed to origin `main`.

## 2026-09-15 16:45 — Account settings rows without their own card
- **What:** `_RowGroup` gained `card` (default true). Account settings passes `card: false`, so its rows draw no edge lines, shadow or surface of their own and sit directly on the account card. Rows, icons, text, dividers and spacing are unchanged. Help and information keeps its card.
- **Why:** User request: remove the card from Account settings only, nothing else.
- **Affected:** `lib/features/account/presentation/account_screen.dart`. `test/account_cards_test.dart`: lifted surfaces 4 -> 3 (outer card, Account, Help).
- **Impact & risk:** Visual only, for Account settings. Routes and behaviour are unchanged.
- **Verification:** analyze clean; account suites 101/101. On the Redmi the settings rows sit on the account card without edges.
- **Commit:** see `git log` — `style(account): drop the account settings rows' own card`, pushed to origin `main`.

## 2026-09-15 16:40 — Whole Account section in one card, Sign out included
- **What:** One `_AccountCard` now holds every Account-section item in its existing order: profile (greeting and email) or guest card, the Orders/Saved/Cart/Support shortcuts, Recently viewed (heading with Clear, and the rail, when there is history), Account settings, Help and information, and Sign out. The split around Recently viewed and the second card are gone. Each item is the same widget with the same spacing and behaviour; `settingsAndHelp` is still defined once.
- **Why:** User request: combine all these items, Recently viewed in place and Sign out included, into one card, changing only the outer container.
- **Affected:** `lib/features/account/presentation/account_screen.dart`. `test/auth_test.dart`: the order test now also asserts Sign out comes last and that Recently viewed, Help and Sign out share one `_AccountCard`.
- **Impact & risk:** Account screen structure only. Items, routes, sign-out confirmation, data and responsive behaviour are unchanged.
- **Verification:** analyze clean; account and related suites 134/134. On the Redmi: one continuous card from "Hello, Prabhakar" to Sign out.
- **Commit:** see `git log` — `style(account): put the whole account section in one card`, pushed to origin `main`.

## 2026-09-15 16:30 — Recently Viewed restored to its original place, outside the card
- **What:** Restored Recently viewed (heading with Clear, and the rail) between the Orders/Saved/Cart/Support shortcuts and Account settings, unchanged: the `_RecentlyViewedRail` widget, `_GroupLabel` Clear action and imports come back from `50924c1`. It sits outside the unified card, so the card splits around it: card 1 holds profile and shortcuts; card 2 holds Account settings and Help. With nothing viewed the page is one card as before. Account settings and Help are written once (`settingsAndHelp`) and reused in either placement.
- **Why:** User request: original location, not inside the card, card unchanged. That spot is inside the card, so the user chose "old spot, split the card in two".
- **Affected:** `lib/features/account/presentation/account_screen.dart`. Tests: `auth_test` (the rail is absent until viewed, then appears; new test for the order shortcuts -> rail -> Account settings), `account_cards_test` (restored comment).
- **Impact & risk:** Account screen layout only. Item look, routes and data are unchanged; `RecentlyViewedStore` is untouched.
- **Verification:** analyze clean; account and related suites 134/134, including `recent_views_section`. On the Redmi: card 1, Recently viewed, card 2 in that order. Note: the profile avatar showed as a black circle on the device. The profile card code is untouched by this change; the app cache shows a photo picked at 16:02, most likely the new avatar.
- **Commit:** see `git log` — `style(account): restore recently viewed to its place, outside the card`, pushed to origin `main`.

## 2026-09-15 16:20 — Recently Viewed removed from the account card
- **What:** Removed the Recently viewed heading (with Clear) and product rail from `_AccountCard` on the Account screen. Also removed what only it used: the `viewed` local, the private `_RecentlyViewedRail` widget, four unused imports, and `_GroupLabel`'s optional Clear action. The other headings render identically (20/20 padding, no button).
- **Why:** User request: remove only Recently Viewed from this card.
- **Affected:** `lib/features/account/presentation/account_screen.dart`. Tests: `auth_test` (the account card no longer shows the rail; visits are still recorded), `account_cards_test` (comment).
- **Impact & risk:** Account card only. `RecentlyViewedStore`, visit recording, the home recent-views section and product history are untouched. Profile, shortcuts, Account settings, Help and information and Sign out are unchanged.
- **Verification:** analyze clean; account and related suites 124/124; `recent_views_section_test` 9/9. On the Redmi: Account settings follows the shortcuts with no rail.
- **Commit:** see `git log` — `style(account): remove recently viewed from the account card`, pushed to origin `main`.

## 2026-09-15 16:10 — Account items combined into one card
- **What:** On the Account screen the profile/guest card, the Orders/Saved/Cart/Support shortcuts, Recently viewed, Account settings and Help and information are wrapped, unchanged, in one `_AccountCard`. It uses the page's own card style (surface colour, `_cardShape`, horizontal hairline border, `_cardLift`) with 12 dp vertical inner padding and no horizontal padding, so nothing inside changes width or position. Sign out stays outside.
- **Why:** User request: place these existing items in one unified card without repositioning or restyling anything.
- **Affected:** `lib/features/account/presentation/account_screen.dart` (wrapper; ignoring whitespace, +49/-2 lines, plus two lines the formatter re-wrapped). `test/account_cards_test.dart` (lifted cards 3 -> 4: the new card plus the three inside).
- **Impact & risk:** Structure only. Items, routes, data and taps are unchanged. The gaps between blocks now show the card's surface instead of the page ground, which is what makes it one card.
- **Verification:** analyze clean; account, login activity, product history, sound, theme and payment suites 135/135. On the Redmi the items read as one card with positions unchanged.
- **Commit:** see `git log` — `style(account): place the account items in one card`, pushed to origin `main`.

## 2026-09-15 15:55 — Flash Sales card radius on the header sections
- **What:** The Delivery + Points card and the Orders / Messages / Notifications section use the Flash Sales card's radius, reused as the constant `AppTheme.radiusCard` (12; was 14). Both surfaces clip content and ripples with `Clip.antiAlias`. The halves' ripple radii follow `DeliveryPointsCard.radius`.
- **Why:** User request: the exact Carousel/Flash Sales radius. The two differ (Flash Sales 12, carousel 16); the user chose Flash Sales (12).
- **Affected:** `delivery_points_card.dart` (`radius = AppTheme.radiusCard`, clip), `search_header.dart` (`_Block` radius + clip), `test/home_category_strip_test.dart` (expects `AppTheme.radiusCard`).
- **Impact & risk:** Corners only. Colours, border, heights, padding, margins, icons, text and taps are unchanged.
- **Verification:** analyze clean; header, tour, home and flash sale suites 168/168. On the Redmi the corners match the Flash Sales card.
- **Commit:** see `git log` — `style(home): header sections take the flash sale card radius`, pushed to origin `main`.

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
