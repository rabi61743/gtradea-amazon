import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../auth/data/auth_store.dart';
import '../data/address_store.dart';

/// Add or edit one address.
///
/// A sheet rather than a page: it is opened from a list or from checkout, and
/// in both cases the shopper is in the middle of something they want to get
/// back to.
///
/// Three things to fill in, not seven: where it goes, which door, and a number
/// to ring. Everything else the shop needs it already knows or can detect.
///
///   * **The name** is the signed-in account's. The checkout payload requires
///     one, so it is still sent -- it is just not asked for twice.
///   * **City and province** are filled by detection and shown as a summary
///     line. They still reach the gateway, which needs the district in both
///     `city` and `state` for freight, but they stop being fields.
///   * **The postal code** is kept when a geocoder supplies one and never
///     typed. Plenty of Nepali addresses have none, so asking was a question
///     most shoppers had to skip.
class AddressFormSheet extends StatefulWidget {
  const AddressFormSheet({
    super.key,
    this.existing,
    this.seed,
    this.seedApproximate = false,
  });

  /// The address being edited, or null when adding a new one.
  final Address? existing;

  /// Values to start a NEW address from -- a city chosen from a chip, say.
  /// Kept separate from [existing] on purpose: a prefilled form is still an
  /// add, and treating it as an edit would try to update a row that has no id
  /// and silently save nothing.
  final Address? seed;

  /// True when the seeded city was a nearest-town guess rather than a real
  /// geocoded address. Surfaced on the city field itself, which is where the
  /// shopper can act on it.
  final bool seedApproximate;

  static Future<Address?> show(
    BuildContext context, {
    Address? existing,
    Address? seed,
    bool seedApproximate = false,
  }) {
    return showModalBottomSheet<Address>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => AddressFormSheet(
        existing: existing,
        seed: seed,
        seedApproximate: seedApproximate,
      ),
    );
  }

  @override
  State<AddressFormSheet> createState() => _AddressFormSheetState();
}

class _AddressFormSheetState extends State<AddressFormSheet> {
  final _formKey = GlobalKey<FormState>();

  Address? get _start => widget.existing ?? widget.seed;

  late final _phone = TextEditingController(text: _start?.phone);
  late final _city = TextEditingController(text: _start?.city);
  late final _area = TextEditingController(text: _start?.area);
  late final _landmark = TextEditingController(text: _start?.landmark);
  late final _postal = TextEditingController(text: _start?.postalCode);

  late final AddressLabel _label = _start?.label ?? AddressLabel.home;

  /// Guarded, not trusted. The dropdown asserts when its value is not among
  /// its items, which would mean the form never opens at all -- so a seed
  /// carrying anything the list does not know falls back to the default
  /// rather than taking the whole sheet down.
  late String _province = kProvinces.contains(_start?.province)
      ? _start!.province
      : kProvinces[2];
  late bool _makeDefault =
      widget.existing == null ||
      AddressStore.instance.isDefault(widget.existing!.id);

  /// Whether the city and province are showing as controls rather than as the
  /// one-line summary.
  ///
  /// Open from the start in the two cases where the summary would be the wrong
  /// answer:
  ///
  ///   * nothing detected, so there is nothing to summarise -- a shopper typing
  ///     an address by hand meets "Edit" over a blank line, which is a puzzle
  ///     rather than an affordance;
  ///   * the city came from the nearest-town fallback, which is precisely when
  ///     it is worth a second look. Hiding a guess behind a summary is how a
  ///     wrong city gets saved without anybody reading it.
  late bool _editingPlace =
      (_start?.city ?? '').trim().isEmpty || widget.seedApproximate;

  bool get _isEditing => widget.existing != null;

  @override
  void dispose() {
    _phone.dispose();
    _city.dispose();
    _area.dispose();
    _landmark.dispose();
    _postal.dispose();
    super.dispose();
  }

  /// Who the parcel is for.
  ///
  /// No longer a field. The checkout payload requires a first and last name and
  /// always sends them, so this cannot simply become empty -- it comes from the
  /// signed-in account instead, which already knows. An address being edited
  /// keeps whatever name it was saved with rather than being quietly rewritten
  /// to the account holder's: somebody may well have addressed it to a relative.
  String get _receiverName {
    final existing = widget.existing?.fullName.trim() ?? '';
    if (existing.isNotEmpty) return existing;
    return AuthStore.instance.account?.displayName ?? '';
  }

  void _save() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final store = AddressStore.instance;

    final Address saved;
    if (_isEditing) {
      saved = widget.existing!.copyWith(
        label: _label,
        fullName: _receiverName,
        phone: _phone.text,
        province: _province,
        city: _city.text,
        area: _area.text,
        landmark: _landmark.text,
        postalCode: _postal.text,
      );
      store.update(saved);
      if (_makeDefault) store.setDefault(saved.id);
    } else {
      saved = store.add(
        label: _label,
        fullName: _receiverName,
        phone: _phone.text,
        province: _province,
        city: _city.text,
        area: _area.text,
        landmark: _landmark.text,
        postalCode: _postal.text,
        makeDefault: _makeDefault,
      );
    }

    Navigator.of(context).pop(saved);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      // Its own Material, so the sheet brings its own surface and ink wherever
      // it is placed rather than only inside a modal route.
      color: theme.colorScheme.surface,
      child: Padding(
        // Lifts the sheet clear of the keyboard, so the field being typed into
        // is never the one hidden behind it.
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.9,
          maxChildSize: 0.95,
          minChildSize: 0.5,
          builder: (context, controller) => Form(
            key: _formKey,
            child: ListView(
              controller: controller,
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
              children: [
                const _Grabber(),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _isEditing ? 'Edit address' : 'New address',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      tooltip: 'Close',
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                _FieldLabel('Where it goes'),
                TextFormField(
                  controller: _area,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  maxLines: 2,
                  minLines: 1,
                  decoration: const InputDecoration(
                    labelText: 'Address',
                    prefixIcon: Icon(Icons.signpost_outlined),
                    helperText: 'Tole, street and house number',
                  ),
                  validator: (value) => (value ?? '').trim().isEmpty
                      ? 'Enter the street and house'
                      : null,
                ),
                const SizedBox(height: 10),

                // The city and province, which the checkout payload needs and
                // which a shopper should not be typing. Detection fills them; the
                // summary lets them be corrected without being two more fields to
                // work through.
                _PlaceSummary(
                  city: _city,
                  province: _province,
                  approximate: widget.seedApproximate,
                  expanded: _editingPlace,
                  onEdit: () => setState(() => _editingPlace = true),
                  onProvinceChanged: (value) =>
                      setState(() => _province = value ?? _province),
                ),
                const SizedBox(height: 14),

                TextFormField(
                  controller: _landmark,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Apartment, floor or unit (optional)',
                    prefixIcon: Icon(Icons.meeting_room_outlined),
                    // Doubles as the landmark line it used to be: plenty of
                    // deliveries here are found by a nearby shop rather than by a
                    // unit number, and both belong on the same second line.
                    helperText: 'Or a nearby landmark, if that helps more',
                    helperMaxLines: 2,
                  ),
                ),
                const SizedBox(height: 8),

                CheckboxListTile(
                  value: _makeDefault,
                  onChanged: (value) =>
                      setState(() => _makeDefault = value ?? false),
                  title: const Text('Deliver here by default'),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: _save,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
                  ),
                  child: Text(_isEditing ? 'Save changes' : 'Save address'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Loose on purpose. Nepali mobile numbers are ten digits, but a landline,
  /// a country code or a spare number written with spaces are all things a
  /// real shopper types, and rejecting them helps nobody.
}

/// The city and province: one quiet line, or two controls.
///
/// They cannot be dropped -- the checkout payload sends the district as both
/// `city` and `state`, and the freight calculation keys on one of them -- but
/// they are also not things a shopper should be typing when detection has
/// already answered them. So they are shown as a summary with a way in, and
/// only become fields when somebody actually disagrees with them.
class _PlaceSummary extends StatelessWidget {
  const _PlaceSummary({
    required this.city,
    required this.province,
    required this.approximate,
    required this.expanded,
    required this.onEdit,
    required this.onProvinceChanged,
  });

  final TextEditingController city;
  final String province;

  /// True when the city came from the nearest-town fallback rather than from a
  /// real geocode. Said plainly, because it is the one case where the summary
  /// is a guess.
  final bool approximate;

  final bool expanded;
  final VoidCallback onEdit;
  final ValueChanged<String?> onProvinceChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (expanded) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: city,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: 'City or district',
              prefixIcon: const Icon(Icons.location_city_outlined),
              helperText: approximate
                  ? 'We guessed this from your rough position -- change it '
                        'if it is wrong'
                  : null,
              helperMaxLines: 2,
            ),
            validator: (value) =>
                (value ?? '').trim().isEmpty ? 'Enter a city' : null,
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            initialValue: province,
            decoration: const InputDecoration(
              labelText: 'Province',
              prefixIcon: Icon(Icons.map_outlined),
            ),
            items: [
              for (final option in kProvinces)
                DropdownMenuItem(value: option, child: Text(option)),
            ],
            onChanged: onProvinceChanged,
          ),
        ],
      );
    }

    return InkWell(
      borderRadius: BorderRadius.circular(AppTheme.radiusControl),
      onTap: onEdit,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Icon(
              approximate ? Icons.help_outline : Icons.location_city_outlined,
              size: 18,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                approximate
                    ? '${city.text}, $province — roughly'
                    : '${city.text}, $province',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'Edit',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        text.toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: 0.8,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// Home / Work / Other as segmented chips.

class _Grabber extends StatelessWidget {
  const _Grabber();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 38,
        height: 4,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.outlineVariant,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}
