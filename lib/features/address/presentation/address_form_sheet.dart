import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_theme.dart';
import '../data/address_store.dart';

/// Add or edit one address.
///
/// A sheet rather than a page: it is opened from a list or from checkout, and
/// in both cases the shopper is in the middle of something they want to get
/// back to.
///
/// Fields are ordered the way an address is spoken here -- who, then how to
/// reach them, then province down to the door -- rather than the way a
/// database would store it.
class AddressFormSheet extends StatefulWidget {
  const AddressFormSheet({super.key, this.existing, this.seed});

  /// The address being edited, or null when adding a new one.
  final Address? existing;

  /// Values to start a NEW address from -- a city chosen from a chip, say.
  /// Kept separate from [existing] on purpose: a prefilled form is still an
  /// add, and treating it as an edit would try to update a row that has no id
  /// and silently save nothing.
  final Address? seed;

  static Future<Address?> show(
    BuildContext context, {
    Address? existing,
    Address? seed,
  }) {
    return showModalBottomSheet<Address>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => AddressFormSheet(existing: existing, seed: seed),
    );
  }

  @override
  State<AddressFormSheet> createState() => _AddressFormSheetState();
}

class _AddressFormSheetState extends State<AddressFormSheet> {
  final _formKey = GlobalKey<FormState>();

  Address? get _start => widget.existing ?? widget.seed;

  late final _name = TextEditingController(text: _start?.fullName);
  late final _phone = TextEditingController(text: _start?.phone);
  late final _city = TextEditingController(text: _start?.city);
  late final _area = TextEditingController(text: _start?.area);
  late final _landmark = TextEditingController(text: _start?.landmark);

  late AddressLabel _label = _start?.label ?? AddressLabel.home;
  late String _province = (_start?.province.isNotEmpty ?? false)
      ? _start!.province
      : kProvinces[2];
  late bool _makeDefault = widget.existing == null ||
      AddressStore.instance.isDefault(widget.existing!.id);

  bool get _isEditing => widget.existing != null;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _city.dispose();
    _area.dispose();
    _landmark.dispose();
    super.dispose();
  }

  void _save() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final store = AddressStore.instance;

    final Address saved;
    if (_isEditing) {
      saved = widget.existing!.copyWith(
        label: _label,
        fullName: _name.text,
        phone: _phone.text,
        province: _province,
        city: _city.text,
        area: _area.text,
        landmark: _landmark.text,
      );
      store.update(saved);
      if (_makeDefault) store.setDefault(saved.id);
    } else {
      saved = store.add(
        label: _label,
        fullName: _name.text,
        phone: _phone.text,
        province: _province,
        city: _city.text,
        area: _area.text,
        landmark: _landmark.text,
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
                      style: theme.textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w800),
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

              _FieldLabel('Save this address as'),
              _LabelPicker(
                selected: _label,
                onChanged: (label) => setState(() => _label = label),
              ),
              const SizedBox(height: 20),

              _FieldLabel('Who is receiving it'),
              TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Full name',
                  prefixIcon: Icon(Icons.person_outline),
                ),
                validator: (value) =>
                    (value ?? '').trim().isEmpty ? 'Enter a name' : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.next,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9+\- ]')),
                ],
                decoration: const InputDecoration(
                  labelText: 'Phone',
                  prefixIcon: Icon(Icons.phone_outlined),
                  helperText: 'The courier calls this number on the day',
                ),
                validator: _validatePhone,
              ),
              const SizedBox(height: 20),

              _FieldLabel('Where it goes'),
              DropdownButtonFormField<String>(
                initialValue: _province,
                decoration: const InputDecoration(
                  labelText: 'Province',
                  prefixIcon: Icon(Icons.map_outlined),
                ),
                items: [
                  for (final province in kProvinces)
                    DropdownMenuItem(value: province, child: Text(province)),
                ],
                onChanged: (value) =>
                    setState(() => _province = value ?? _province),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _city,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'City or district',
                  prefixIcon: Icon(Icons.location_city_outlined),
                ),
                validator: (value) =>
                    (value ?? '').trim().isEmpty ? 'Enter a city' : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _area,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                maxLines: 2,
                minLines: 1,
                decoration: const InputDecoration(
                  labelText: 'Tole, street and house number',
                  prefixIcon: Icon(Icons.signpost_outlined),
                ),
                validator: (value) => (value ?? '').trim().isEmpty
                    ? 'Enter the street and house'
                    : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _landmark,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _save(),
                decoration: const InputDecoration(
                  labelText: 'Landmark (optional)',
                  prefixIcon: Icon(Icons.storefront_outlined),
                  // Not decoration: plenty of deliveries here are found by
                  // landmark rather than by street number.
                  helperText: 'A shop or building nearby helps the courier',
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
  static String? _validatePhone(String? value) {
    final digits = (value ?? '').replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return 'Enter a phone number';
    if (digits.length < 7) return 'That looks too short';
    return null;
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
class _LabelPicker extends StatelessWidget {
  const _LabelPicker({required this.selected, required this.onChanged});

  final AddressLabel selected;
  final ValueChanged<AddressLabel> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        for (final label in AddressLabel.values) ...[
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(AppTheme.radiusControl),
              onTap: () => onChanged(label),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                padding: const EdgeInsets.symmetric(vertical: 11),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppTheme.radiusControl),
                  color: label == selected
                      ? theme.colorScheme.primary.withValues(alpha: 0.10)
                      : null,
                  border: Border.all(
                    color: label == selected
                        ? theme.colorScheme.primary
                        : theme.colorScheme.outlineVariant,
                    width: label == selected ? 1.5 : 1,
                  ),
                ),
                child: Column(
                  children: [
                    Icon(
                      label.icon,
                      size: 19,
                      color: label == selected
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      label.title,
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: label == selected
                            ? FontWeight.w800
                            : FontWeight.w500,
                        color: label == selected
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (label != AddressLabel.values.last) const SizedBox(width: 10),
        ],
      ],
    );
  }
}

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
