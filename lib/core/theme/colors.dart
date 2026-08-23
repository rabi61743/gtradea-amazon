import 'package:flutter/material.dart';

/// GtradeA brand palette, ported 1:1 from the web storefront
/// (`GTR1/src/index.css` HSL tokens + `tailwind.config.js`).
///
/// The web app is a shadcn/ui "slate" base customized with a teal primary,
/// a warm-cream secondary/muted, and a tomato accent. Values here are the
/// hex conversions of the authoritative HSL variables.
class AppColors {
  AppColors._();

  // ── Brand ────────────────────────────────────────────────────────────────
  /// `--primary` 191 55% 34%  (light) / 191 55% 45% (dark)
  static const Color primaryLight = Color(0xFF277586);
  static const Color primaryDark = Color(0xFF349BB2);
  static const Color onPrimary = Color(0xFFFFFFFF);

  /// `--accent` 9 81% 53% (tomato — used sparingly)
  static const Color accent = Color(0xFFE84326);
  static const Color onAccent = Color(0xFFFFFFFF);

  // ── Surfaces ──────────────────────────────────────────────────────────────
  static const Color backgroundLight = Color(0xFFFFFFFF);
  static const Color backgroundDark = Color(0xFF020817);
  static const Color foregroundLight = Color(0xFF020817);
  static const Color foregroundDark = Color(0xFFF8FAFC);

  // Card == background in this theme.
  static const Color cardLight = Color(0xFFFFFFFF);
  static const Color cardDark = Color(0xFF020817);

  /// `--secondary` / `--muted`: warm cream (light) / slate (dark).
  static const Color mutedLight = Color(0xFFF3EDE7);
  static const Color mutedDark = Color(0xFF1E293B);
  static const Color mutedForegroundLight = Color(0xFF64748B);
  static const Color mutedForegroundDark = Color(0xFF94A3B8);

  static const Color borderLight = Color(0xFFE2E8F0);
  static const Color borderDark = Color(0xFF1E293B);

  // ── Destructive / error ────────────────────────────────────────────────────
  static const Color destructiveLight = Color(0xFFEF4444);
  static const Color destructiveDark = Color(0xFF7F1D1D);
  static const Color onDestructive = Color(0xFFF8FAFC);

  // ── Hard-coded semantic colors (Tailwind palette literals in the web app) ──
  /// Delivered / success / "ahead of schedule" (emerald-600).
  static const Color success = Color(0xFF059669);

  /// Current / in-progress tracking node (orange-500, pulsing on web).
  static const Color inProgress = Color(0xFFF97316);

  /// "Behind schedule" (amber-700).
  static const Color warning = Color(0xFFB45309);

  // Shipment-mode chips.
  static const Color shipAir = Color(0xFF0EA5E9); // sky-500
  static const Color shipSea = Color(0xFF0891B2); // cyan-600
  static const Color shipLand = Color(0xFF2563EB); // blue-600

  // Misc UI accents.
  static const Color star = Color(0xFFFACC15); // yellow-400
  static const Color wishlist = Color(0xFFEF4444); // red-500
  static const Color esewa = Color(0xFF16A34A); // green-600
}
