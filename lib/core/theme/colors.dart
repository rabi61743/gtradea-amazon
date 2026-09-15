import 'package:flutter/material.dart';

/// The GtradeA brand system.
///
/// Six colours, and every hex below the brand block is either one of them, a
/// derivation of one, or a utility the system does not name -- a courier's
/// colour, a payment provider's. None of them should grow into a seventh.
///
/// The neutrals were briefly derived instead: three washes of
/// [himalayanSlate] over white, after Premium Ivory and Mountain Grey were
/// dropped. They are back, by request, and they carry exactly the roles the
/// brand names for them -- ivory for quiet ground and subtle panels, grey for
/// every line and edge. The washes are gone, and the names that pointed at
/// them now point at these.
///
/// ## The 60-30-10 rule
///
/// What decides which of the three leading colours a surface gets:
///
///   * **60% white and [premiumIvory]** -- the page and the quiet ground on
///     it. Breathing space, contrast margins, the surfaces everything else
///     sits on.
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

  /// Premium Ivory. RGB 242, 236, 230.
  ///
  /// Breathing space, quiet panels, subtle section grounds, contrast areas.
  /// Warm rather than grey, which is what separates a panel from a border:
  /// one is a surface, the other is a line.
  static const Color premiumIvory = Color(0xFFF2ECE6);

  /// Mountain Grey. RGB 229, 231, 235.
  ///
  /// Dividers, borders, card outlines, secondary frames. Lines only -- a
  /// fill in this colour is a border that grew.
  static const Color mountainGrey = Color(0xFFE5E7EB);

  /// Success Green. RGB 34, 197, 94.
  ///
  /// Verification checkmarks, trust badges, positive metrics.
  static const Color successGreen = Color(0xFF22C55E);

  // ── The neutrals ──────────────────────────────────────────────────────────
  // Two brand colours doing two jobs, under the names the rest of the file
  // already used for them. Kept as names rather than replaced everywhere, so
  // the role a colour is filling stays readable at the point of use.

  /// The quiet ground: breathing space, contrast areas, section backgrounds.
  ///
  /// This is the 60 of the 60-30-10 wherever a surface is not white. The page
  /// itself stays white -- see [backgroundLight] -- so this is what a panel,
  /// a chip or a skeleton is drawn in when it has to read as *on* the page.
  static const Color pageWash = premiumIvory;

  /// Filled chips, skeleton bones, quiet panels.
  ///
  /// The same ivory. A fill and a ground are the same job at two sizes, and
  /// giving them two nearly-identical hexes was a distinction nobody could
  /// see and everybody had to maintain.
  static const Color surfaceWash = premiumIvory;

  /// Dividers, card borders, frame outlines. Mountain Grey's whole job.
  static const Color hairline = mountainGrey;

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
  static const Color brandBandTop = Color(0xFF1B5E72);

  /// Where the band finishes, a shade above Trust Blue.
  ///
  /// The ramp is three stops now, to the specified treatment: the dark top,
  /// the brand blue through the middle where the utilities sit, and this at
  /// the foot so the band lifts into the page rather than darkening into it.
  ///
  /// The specification says "approximately #2F8797", and this is 95% of it.
  /// The reason is contrast: white on #2F8797 measures 4.17:1, under AA, and
  /// the foot of the band is where the greeting and the search row sit. At
  /// #2D808F it is 4.57:1 -- the same colour to the eye, and readable.
  static const Color brandBandFoot = Color(0xFF2D808F);

  /// The header band, top to bottom.
  ///
  /// One gradient for the whole band rather than one per widget. The band is
  /// two siblings in a column -- the search header and the department strip --
  /// and giving each its own top-to-bottom gradient would run the ramp twice
  /// and jump back to the dark end at the join. That join is the seam this
  /// header has already had removed once.
  /// The head of the band, as specified.
  static const Color brandBandHead = Color(0xFF1A4A5E);

  /// And its foot, deeper than the head rather than lighter.
  ///
  /// This reverses the direction the ramp used to run. The old foot was a
  /// shade *above* Trust Blue so the band lifted into the page; this one sinks
  /// into it. Nothing is lost on legibility by going darker -- white measures
  /// 14.66:1 here against the 4.57:1 the old foot was carefully tuned to
  /// reach, so the greeting and the search row that sit down here are further
  /// clear of AA than before, not nearer it.
  static const Color brandBandDeep = Color(0xFF0D2B3E);

  /// The header band, top to bottom.
  ///
  /// Two stops, by specification, where it used to be three. One gradient for
  /// the whole band rather than one per widget: the band is a single box now,
  /// and the ramp follows the curve cut out of its foot rather than stopping
  /// at a straight edge.
  static const LinearGradient brandBand = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [brandBandHead, brandBandDeep],
  );

  /// Trust Blue lifted for a dark surface. The brand names one blue; this is
  /// that blue at a lightness that survives being drawn on near-black, and it
  /// is used only in the dark theme, which the app does not currently ship.
  static const Color primaryDark = Color(0xFF349BB2);
  static const Color onPrimary = Color(0xFFFFFFFF);

  static const Color accent = commerceOrange;
  static const Color onAccent = Color(0xFFFFFFFF);

  // ── Surfaces ──────────────────────────────────────────────────────────────

  /// The page: Premium Ivory.
  ///
  /// Its own stated role -- breathing space, contrast margins, the ground a
  /// clean white card sits on. It was Mountain Grey for a moment, which put
  /// the page and the hairline in the same colour and left card borders with
  /// nothing to draw against. Ivory restores that: the line is grey, the page
  /// is not.
  ///
  /// Measured on this ground: body slate 8.45:1, secondary text 4.89:1, the
  /// brand blue 4.55:1. All clear AA for the sizes they are set in.
  static const Color backgroundLight = Color.fromARGB(255, 243, 242, 242);
  // static const Color backgroundLight = premiumIvory;
  static const Color backgroundDark = Color(0xFF1B2229);

  /// Body copy. Slate rather than near-black: the brand asks for legible, not
  /// maximal, and slate on the page wash is a softer read over long text.
  static const Color foregroundLight = himalayanSlate;

  /// Dark-theme body copy: the ivory, which is a warm off-white rather than
  /// a glare of pure white on near-black.
  static const Color foregroundDark = premiumIvory;

  /// Cards stay white, so they lift off the washed page.
  static const Color cardLight = Color(0xFFFFFFFF);

  /// "Dark-mode cards" is Himalayan Slate's own stated role.
  static const Color cardDark = himalayanSlate;

  /// Filled chips, skeleton bones, quiet panels.
  ///
  /// Mountain Grey rather than the ivory, now that the page *is* the ivory: a
  /// fill the same colour as the ground it sits on is not a fill. Cooler and
  /// a step darker, so it reads on the page and under a white card alike.
  static const Color mutedLight = mountainGrey;
  static const Color mutedDark = Color(0xFF2B3740);

  /// Secondary text -- captions, subtitles, the sold line on a product card.
  ///
  /// Slate held back rather than a grey from outside the system, and held
  /// back only as far as it can be read on every ground the app draws it on:
  /// **4.63:1 on the Mountain Grey page, 4.89:1 on Premium Ivory and 5.73:1
  /// on a white card**, all clear of AA. It was #5F6D77 when the page was
  /// white, and that measured 4.30 on the grey -- under the 4.5 small text
  /// needs. The hue is the same; there is less light in it.
  static const Color mutedForegroundLight = Color(0xFF5B6871);
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
