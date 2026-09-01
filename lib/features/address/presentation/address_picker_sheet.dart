import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../auth/data/auth_store.dart';
import '../data/address_store.dart';
import 'use_my_location_tile.dart';
import 'address_form_sheet.dart';

/// Choose where an order is going.
///
/// A sheet, because picking an address is a step inside checkout rather than a
/// place to be. It returns the chosen [Address], or null if the shopper backed
/// out without deciding.
///
/// Two things here differ from how a large storefront usually does this, both
/// deliberate:
///
/// A guest is not blocked. The reference this was drawn from puts a padlock
/// and a "log in to see saved addresses" wall in front of the whole sheet.
/// This app lets guests place orders, so refusing to remember where one goes
/// would be perverse. Guests save addresses to their own book and it follows
/// them into their account when they sign in; the sheet says so rather than
/// leaving it as a surprise.
///
/// "Use my current location" fills in the city, and says so. There is no
/// geocoder here, so [LocationDetector] matches the fix to the nearest city
/// this shop serves -- which answers the question the form actually needs
/// answered, and works with no network. The wording promises the town rather
/// than the doorstep, because the town is what it knows. Every way it can fail
/// -- location off, permission refused, refused for good, nowhere near a
/// served city -- gets its own message, since "something went wrong" leaves a
/// shopper with nothing to do next.
class AddressPickerSheet extends StatefulWidget {
  const AddressPickerSheet({super.key, this.selectedId});

  final String? selectedId;

  static Future<Address?> show(BuildContext context, {String? selectedId}) {
    return showModalBottomSheet<Address>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => AddressPickerSheet(selectedId: selectedId),
    );
  }

  @override
  State<AddressPickerSheet> createState() => _AddressPickerSheetState();
}

class _AddressPickerSheetState extends State<AddressPickerSheet> {
  final _search = TextEditingController();
  String _query = '';

  /// The cities most of this shop's orders go to. Tapping one opens the form
  /// with the slow parts already filled.
  static const _quickCities = <(String city, String province)>[
    ('Kathmandu', 'Bagmati'),
    ('Lalitpur', 'Bagmati'),
    ('Bhaktapur', 'Bagmati'),
    ('Pokhara', 'Gandaki'),
    ('Biratnagar', 'Koshi'),
    ('Butwal', 'Lumbini'),
  ];

  @override
  void initState() {
    super.initState();
    AddressStore.instance.load();
    AuthStore.instance.load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _addNew([DetectedPlace? found]) async {
    final created = await AddressFormSheet.show(
      context,
      // A seed, not an edit: the form opens with whatever was worked out and
      // the cursor free for the parts only the shopper knows.
      seed: found == null
          ? null
          : Address(
              id: '',
              label: AddressLabel.home,
              fullName: AuthStore.instance.account?.displayName ?? '',
              phone: '',
              province: found.province,
              city: found.city,
              area: found.addressLine ?? '',
              postalCode: found.postalCode,
            ),
      seedApproximate: found?.approximate ?? false,
    );
    if (created != null && mounted) Navigator.of(context).pop(created);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([AddressStore.instance, AuthStore.instance]),
      builder: (context, _) {
        final store = AddressStore.instance;
        final matches = store.search(_query);
        final signedIn = AuthStore.instance.isSignedIn;

        // Its own Material, so the sheet brings its own surface and ink
        // wherever it is placed rather than only inside a modal route.
        return Material(
          color: Theme.of(context).colorScheme.surface,
          child: DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.82,
            maxChildSize: 0.95,
            minChildSize: 0.5,
            builder: (context, controller) => Column(
              children: [
                const SizedBox(height: 8),
                const _Grabber(),
                _Header(onClose: () => Navigator.of(context).pop()),
                if (store.count > 2)
                  _SearchField(
                    controller: _search,
                    onChanged: (value) => setState(() => _query = value),
                  ),
                Expanded(
                  child: ListView(
                    controller: controller,
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                    children: [
                      UseMyLocationTile(onDetected: _addNew),
                      const SizedBox(height: 16),
                      if (store.isEmpty)
                        _NoAddresses(
                          signedIn: signedIn,
                          quickCities: _quickCities,
                          onPick: (city, province) => _addNew((
                            city: city,
                            province: province,
                            addressLine: null,
                            postalCode: null,
                            approximate: false,
                          )),
                        )
                      else ...[
                        if (matches.isEmpty)
                          _NoMatches(query: _query)
                        else
                          for (final address in matches)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: _AddressCard(
                                address: address,
                                isSelected:
                                    address.id ==
                                    (widget.selectedId ??
                                        store.defaultAddress?.id),
                                isDefault: store.isDefault(address.id),
                                onTap: () => Navigator.of(context).pop(address),
                                onEdit: () async {
                                  final edited = await AddressFormSheet.show(
                                    context,
                                    existing: address,
                                  );
                                  if (edited != null && context.mounted) {
                                    Navigator.of(context).pop(edited);
                                  }
                                },
                              ),
                            ),
                        const SizedBox(height: 6),
                        if (!signedIn) const _GuestNote(),
                      ],
                    ],
                  ),
                ),
                _AddButton(onPressed: () => _addNew()),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 8, 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Deliver to',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Pick an address or add a new one',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: 'Close',
            onPressed: onClose,
          ),
        ],
      ),
    );
  }
}

/// Detect the shopper's city rather than make them type it.
///
/// States what it will actually do -- fill in the city -- instead of promising
/// to fill the whole address. It can name the town, not the door.
/// Only shown once the book is big enough to need it. A search box above two
/// addresses is furniture.
class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: 'Search name, area or city',
          prefixIcon: const Icon(Icons.search),
          isDense: true,
          suffixIcon: controller.text.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.clear, size: 18),
                  tooltip: 'Clear',
                  onPressed: () {
                    controller.clear();
                    onChanged('');
                  },
                ),
        ),
      ),
    );
  }
}

class _AddressCard extends StatelessWidget {
  const _AddressCard({
    required this.address,
    required this.isSelected,
    required this.isDefault,
    required this.onTap,
    required this.onEdit,
  });

  final Address address;
  final bool isSelected;
  final bool isDefault;
  final VoidCallback onTap;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      borderRadius: BorderRadius.circular(AppTheme.radiusCard),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppTheme.radiusCard),
          color: isSelected
              ? theme.colorScheme.primary.withValues(alpha: 0.06)
              : null,
          border: Border.all(
            color: isSelected
                ? theme.colorScheme.primary
                : theme.colorScheme.outlineVariant,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: theme.colorScheme.primary.withValues(alpha: 0.10),
              ),
              child: Icon(
                address.label.icon,
                size: 18,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      // No headline. It used to be the name, which the form no
                      // longer asks for, and swapping the address in printed it
                      // twice over the full line just below. The tags lead and
                      // the address speaks for itself.
                      _Tag(text: address.label.title),
                      if (isDefault) ...[
                        const SizedBox(width: 6),
                        _Tag(text: 'Default', tone: theme.colorScheme.primary),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    address.full,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.35,
                    ),
                  ),
                  if (address.phone.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      address.phone,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 18),
              tooltip: 'Edit',
              visualDensity: VisualDensity.compact,
              onPressed: onEdit,
            ),
          ],
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.text, this.tone});

  final String text;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colour = tone ?? theme.colorScheme.onSurfaceVariant;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: theme.textTheme.labelSmall?.copyWith(
          color: colour,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// The empty state, which is where the reference put a padlock.
///
/// This one offers a way forward instead: the cities most orders go to, each
/// opening the form with the slow half already filled.
class _NoAddresses extends StatelessWidget {
  const _NoAddresses({
    required this.signedIn,
    required this.quickCities,
    required this.onPick,
  });

  final bool signedIn;
  final List<(String, String)> quickCities;
  final void Function(String city, String province) onPick;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: theme.colorScheme.primary.withValues(alpha: 0.10),
              ),
              child: Icon(
                Icons.location_on_outlined,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'No addresses yet',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Add one and we will remember it for next time.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 22),
        Text(
          'START WITH A CITY',
          style: theme.textTheme.labelSmall?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (city, province) in quickCities)
              ActionChip(
                avatar: const Icon(Icons.location_city_outlined, size: 16),
                label: Text(city),
                onPressed: () => onPick(city, province),
              ),
          ],
        ),
        const SizedBox(height: 20),
        if (!signedIn) const _GuestNote(),
      ],
    );
  }
}

class _NoMatches extends StatelessWidget {
  const _NoMatches({required this.query});

  final String query;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: Center(
        child: Text(
          'No saved address matches "$query".',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

/// Said plainly rather than enforced with a wall.
class _GuestNote extends StatelessWidget {
  const _GuestNote();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      ),
      child: Row(
        children: [
          Icon(
            Icons.info_outline,
            size: 18,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'You are shopping as a guest. Addresses you save here come with '
              'you when you sign in.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AddButton extends StatelessWidget {
  const _AddButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      top: false,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: theme.dividerColor)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
        child: FilledButton.icon(
          onPressed: onPressed,
          icon: const Icon(Icons.add, size: 20),
          label: const Text('Add a new address'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        ),
      ),
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
