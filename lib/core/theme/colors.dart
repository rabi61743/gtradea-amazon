import 'package:flutter/material.dart';

/// The GtradeA brand system.
///
/// These four are the brand. Every hex below the brand block is either derived
/// from one of them or a utility the system does not name -- a courier's
/// colour, a payment provider's -- and none of them should grow into a fifth
/// brand colour.
///
/// Premium Ivory and Mountain Grey used to sit here as the fifth and sixth.
/// They are gone. What they were doing has not gone with them: a page still
/// needs a ground and a card still needs an edge, so both roles are now filled
/// by [himalayanSlate] laid over white at a stated alpha -- [pageWash],
/// [surfaceWash] and [hairline] below. That keeps the neutrals tied to a brand
/// colour instead of being two more hexes nobody can derive, and it drops the
/// warm cast the ivory put over every screen.
///
/// ## The 60-30-10 rule
///
/// What decides which of the three leading colours a surface gets:
///
///   * **60% [pageWash]** -- the page itself. Breathing space, contrast
///     margins, the ground everything sits on. It is the scaffold background,
///     which is why cards read as cards: they are white *on* something.
///   * **30% [trustBlue]** -- structure. The header band, navigation, overlay
///     bars, anything making a statement the shopper is asked to trust.
///   * **10% [commerceOrange]** -- and no more. Calls to action, promotional
///     badges, flash-sale stickers, the one thing on a screen meant to be
///     pressed. An orange used for a fourth thing is an orange that has stopped
///     meaning "press this".
///
/// The ratio is a budget, not a decoration: if a new screen wants orange in
/// three places, two of them are wrong.
class AppColors {
  AppColors._();

  // ── The brand ─────────────────────────────────────────────────────────────

  /// Trust Blue. RGB 38, 116, 136.
  ///
  /// Primary brand foundation, overlay bars, trust statements, UI navigation.
  /// The 30 of the 60-30-10.
  static const Color trustBlue = Color(0xFF267488);

  /// Commerce Orange. RGB 233, 71, 36.
  ///
  /// High-converting CTAs, promotional badges, flash-sale stickers, main hooks.
  /// The 10, and it is a ceiling rather than a target.
  static const Color commerceOrange = Color(0xFFE94724);

  /// Himalayan Slate. RGB 54, 69, 79.
  ///
  /// Body text, long-form copy, high-legibility subtitles, dark-mode cards --
  /// and, since the two neutrals were dropped, the source of every neutral in
  /// the light theme.
  static const Color himalayanSlate = Color(0xFF36454F);

  /// Success Green. RGB 34, 197, 94.
  ///
  /// Verification checkmarks, trust badges, positive metrics.
  static const Color successGreen = Color(0xFF22C55E);

  // ── The neutrals, derived ─────────────────────────────────────────────────
  // Three washes of Himalayan Slate over white, at 6%, 8% and 14%. Written as
  // literals because they are used in const contexts and alphaBlend is not a
  // const expression -- so a test pins each one to its own blend, the same way
  // trustBlueDeep's derivation is pinned. Change the alpha there and the test
  // says what the new literal has to be.

  /// The ground the app sits on: Himalayan Slate at 6% over white.
  ///
  /// This is the 60. Not white, because white cards on a white page are edges
  /// rather than cards; not ivory, because the brand no longer has one.
  static const Color pageWash = Color(0xFFF3F4F4);

  /// Filled chips, skeleton bones, quiet panels: slate at 8% over white.
  ///
  /// A step darker than [pageWash] so a muted fill still reads *on* the page,
  /// which is the job the old Mountain Grey was doing here.
  static const Color surfaceWash = Color(0xFFEFF0F1);

  /// Dividers, card borders, frame outlines: slate at 14% over white.
  static const Color hairline = Color(0xFFE3E5E6);

  // ── Mapped onto the theme ─────────────────────────────────────────────────
  // The names below are what the widgets already ask for. Each is one of the
  // four brand colours or a wash of one, so a brand change happens in the
  // block above and nowhere else.

  static const Color primaryLight = trustBlue;

  /// Trust Blue, deepened, for the strip above the search bar.
  ///
  /// Not a seventh brand colour: it is [trustBlue] with its lightness dropped
  /// 0.06 (0.341 to 0.281), hue and saturation untouched. A test pins that
  /// derivation, so it follows the brand blue if the brand blue ever moves
  /// rather than drifting into a shade of its own.
  ///
  /// It exists to give the header two zones: the chrome at the top sits back,
  /// and the search bar reads as the thing on top of it. White on this is
  /// 6.0:1, better than on Trust Blue itself, so nothing in the row loses
  /// contrast by moving onto it.
  static const Color trustBlueDeep = Color(0xFF1F6070);

  /// The top of the header band: Trust Blue taken down to a lightness of
  /// 0.186, from its own 0.341.
  ///
  /// Not a fifth brand colour, and measurably not: its hue is 192.4 degrees
  /// against the brand blue's 192.2, so it is the same colour with the light
  /// turned down. A test pins that, as it does for [trustBlueDeep].
  ///
  /// White on this is 10.5:1 -- better than on Trust Blue itself, so nothing in
  /// the header row loses contrast by sitting at the top of the band.
  static const Color brandBandTop = Color(0xFF10424F);

  /// The header band, top to bottom.
  ///
  /// One gradient for the whole band rather than one per widget. The band is
  /// two siblings in a column -- the search header and the department strip --
  /// and giving each its own top-to-bottom gradient would run the ramp twice
  /// and jump back to the dark end at the join. That join is the seam this
  /// header has already had removed once.
  static const LinearGradient brandBand = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [brandBandTop, trustBlue],
  );

  /// Trust Blue lifted for a dark surface. The brand names one blue; this is
  /// that blue at a lightness that survives being drawn on near-black, and it
  /// is used only in the dark theme, which the app does not currently ship.
  static const Color primaryDark = Color(0xFF349BB2);
  static const Color onPrimary = Color(0xFFFFFFFF);

  static const Color accent = commerceOrange;
  static const Color onAccent = Color(0xFFFFFFFF);

  // ── Surfaces ──────────────────────────────────────────────────────────────

  /// The page: plain white.
  ///
  /// This was [pageWash], a 6% slate over white, so that a white card read as a
  /// card rather than as an edge. It is white now because that is what was
  /// asked for, and the consequence is worth knowing: a card and the page are
  /// the same colour, so what separates them is their hairline border and
  /// nothing else. Every card in this app draws one, which is why the change
  /// is safe -- but a new card without a border will be invisible.
  static const Color backgroundLight = Color(0xFFFFFFFF);
  static const Color backgroundDark = Color(0xFF1B2229);

  /// Body copy. Slate rather than near-black: the brand asks for legible, not
  /// maximal, and slate on the page wash is a softer read over long text.
  static const Color foregroundLight = himalayanSlate;
  static const Color foregroundDark = pageWash;

  /// Cards stay white, so they lift off the washed page.
  static const Color cardLight = Color(0xFFFFFFFF);

  /// "Dark-mode cards" is Himalayan Slate's own stated role.
  static const Color cardDark = himalayanSlate;

  /// Filled chips, skeleton bones, quiet panels.
  ///
  /// A step darker than the page rather than the same wash: a muted surface has
  /// to read on the page *and* on a white card, and a fill the same colour as
  /// the page it sits on is invisible.
  static const Color mutedLight = surfaceWash;
  static const Color mutedDark = Color(0xFF2B3740);

  /// Secondary text -- captions, subtitles, the sold line on a product card.
  /// Slate held back rather than a grey from outside the system.
  static const Color mutedForegroundLight = Color(0xFF6B7A85);
  static const Color mutedForegroundDark = Color(0xFFAFBAC2);

  static const Color borderLight = hairline;
  static const Color borderDark = Color(0xFF44535D);

  // ── Destructive / error ───────────────────────────────────────────────────
  static const Color destructiveLight = Color(0xFFEF4444);
  static const Color destructiveDark = Color(0xFF7F1D1D);
  static const Color onDestructive = Color(0xFFF8FAFC);

  // ── Semantic ──────────────────────────────────────────────────────────────

  /// Verification checkmarks, trust badges, positive metrics.
  ///
  /// **This is a fill, not an ink.** Measured, not assumed:
  ///
  ///   * Success Green as text on the page -- **2.07:1**
  ///   * Success Green as text on white -- **2.28:1**
  ///   * white text on Success Green -- **2.28:1**
  ///
  /// Readable body text wants 4.5:1 and large text 3:1, so all three fail --
  /// including white on green, which is how a badge is usually built. Use it as
  /// the fill behind a *shape* (a tick, a bar, a dot) or behind dark text, and
  /// use [successInk] wherever the same meaning has to be carried by words.
  static const Color success = successGreen;

  /// Success Green at a lightness that can be read.
  ///
  /// The same hue (142 degrees against the brand green's 145) taken down until
  /// it clears AA: **5.34:1 on the page, 5.89:1 on white**. Derived from the brand
  /// colour rather than borrowed from outside it, so "positive" is one hue
  /// across the app whether it appears as a badge or as a sentence.
  static const Color successInk = Color(0xFF0F7434);

  /// Current / in-progress tracking node.
  static const Color inProgress = commerceOrange;

  /// "Behind schedule" (amber-700).
  static const Color warning = Color(0xFFB45309);

  // Shipment-mode chips. Couriers, not brand.
  static const Color shipAir = Color(0xFF0EA5E9); // sky-500
  static const Color shipSea = Color(0xFF0891B2); // cyan-600
  static const Color shipLand = Color(0xFF2563EB); // blue-600

  // ── The flash-sale card ───────────────────────────────────────────────────
  // One block on the home page is a filled red card rather than a white one.
  // That is a deliberate exception to the 60-30-10 budget and worth naming as
  // one: the rule reserves the accent for "the one thing on a screen meant to
  // be pressed", and on the home page this is that thing -- a deadline whose
  // value goes to zero if it is scrolled past. It is one card, and nothing else
  // on the page borrows the treatment.

  /// The top of the flash-sale card: Commerce Orange at 42% lightness.
  ///
  /// Derived, not picked -- hue 10.7 degrees and 82% saturation are the brand
  /// accent's own, with only the lightness lowered, the same way
  /// [trustBlueDeep] is derived from [trustBlue]. A test pins that.
  ///
  /// **Why not the brighter red the design showed.** Measured: white body copy
  /// on that red is **4.05:1**, and on Commerce Orange itself 3.90:1 -- both
  /// under the 4.5 that ordinary text needs. The subhead on this card is
  /// ordinary text. At this lightness it is **5.55:1**, and the deeper end
  /// below is 7.30:1, so every word on the card is readable at the size it is
  /// actually set in. The colour is the same red; there is less light in it.
  static const Color flashSaleTop = Color(0xFFC33213);

  /// The bottom of the card: the same hue at 35% lightness.
  static const Color flashSaleBottom = Color(0xFFA22A10);

  /// Top-left to bottom-right, as the design has it.
  static const LinearGradient flashSaleBand = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [flashSaleTop, flashSaleBottom],
  );

  /// "Hurry up!" -- the one word on the card that is not white.
  ///
  /// Paler than [star], and measurably so on purpose: the yellow the design
  /// used reads **3.87:1** on this ground and yellow-400 only 3.62:1, both
  /// under AA for a word set at body size. This one is **4.65:1** at the
  /// lightest point of the card and 6.12:1 at the darkest.
  static const Color flashSaleHurry = Color(0xFFFFEB99);

  // Misc UI accents.
  static const Color star = Color(0xFFFACC15); // yellow-400
  static const Color wishlist = commerceOrange;
  static const Color esewa = Color(0xFF16A34A); // the provider's own green
}
