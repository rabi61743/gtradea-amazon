import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../data/address_store.dart';
import 'address_form_sheet.dart';
import 'use_my_location_tile.dart';

/// The address book, for managing rather than choosing.
///
/// Reached from the account page. The picker sheet is the version used inside
/// checkout; this one adds the things you only want when you are tidying up --
/// setting a default and deleting.
class AddressListScreen extends StatefulWidget {
  const AddressListScreen({super.key});

  @override
  State<AddressListScreen> createState() => _AddressListScreenState();
}

class _AddressListScreenState extends State<AddressListScreen> {
  @override
  void initState() {
    super.initState();
    AddressStore.instance.load();
  }

  Future<void> _confirmDelete(Address address) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete this address?'),
        content: Text(
          '${address.fullName}, ${address.oneLine}. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep it'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed ?? false) AddressStore.instance.remove(address.id);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AddressStore.instance,
      builder: (context, _) {
        final store = AddressStore.instance;
        final addresses = store.addresses;

        return Scaffold(
          appBar: AppBar(title: const Text('Delivery addresses')),
          body: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                  children: [
                    // Offered here as well as at checkout: adding an address
                    // from the account page benefits from it just as much, and
                    // one widget serves both.
                    UseMyLocationTile(
                      onDetected: (found) => AddressFormSheet.show(
                        context,
                        seed: Address(
                          id: '',
                          label: AddressLabel.home,
                          fullName: '',
                          phone: '',
                          province: found.province,
                          city: found.city,
                          area: found.addressLine ?? '',
                          postalCode: found.postalCode,
                        ),
                        seedApproximate: found.approximate,
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (addresses.isEmpty) const _EmptyBook(),
                    for (final address in addresses)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _AddressRow(
                          address: address,
                          isDefault: store.isDefault(address.id),
                          onEdit: () => AddressFormSheet.show(
                            context,
                            existing: address,
                          ),
                          onMakeDefault: () => store.setDefault(address.id),
                          onDelete: () => _confirmDelete(address),
                        ),
                      ),
                  ],
                ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => AddressFormSheet.show(context),
            icon: const Icon(Icons.add),
            label: const Text('Add address'),
          ),
        );
      },
    );
  }
}

class _AddressRow extends StatelessWidget {
  const _AddressRow({
    required this.address,
    required this.isDefault,
    required this.onEdit,
    required this.onMakeDefault,
    required this.onDelete,
  });

  final Address address;
  final bool isDefault;
  final VoidCallback onEdit;
  final VoidCallback onMakeDefault;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(
          color: isDefault
              ? theme.colorScheme.primary.withValues(alpha: 0.5)
              : theme.colorScheme.outlineVariant,
          width: isDefault ? 1.5 : 1,
        ),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: theme.colorScheme.primary.withValues(alpha: 0.10),
                  ),
                  child: Icon(
                    address.label.icon,
                    size: 19,
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
                          Flexible(
                            child: Text(
                              address.fullName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyLarge
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.onSurfaceVariant
                                  .withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              address.label.title,
                              style: theme.textTheme.labelSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
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
              ],
            ),
          ),
          Divider(height: 1, color: theme.colorScheme.outlineVariant),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            child: Row(
              children: [
                // Stated rather than offered, when it already is the default:
                // a button that does nothing is worse than a label.
                if (isDefault)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.check_circle,
                          size: 16,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Default address',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  TextButton(
                    onPressed: onMakeDefault,
                    child: const Text('Set as default'),
                  ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 19),
                  tooltip: 'Edit',
                  onPressed: onEdit,
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 19),
                  tooltip: 'Delete',
                  color: theme.colorScheme.error,
                  onPressed: onDelete,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyBook extends StatelessWidget {
  const _EmptyBook();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.location_on_outlined,
              size: 44,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              'No addresses saved',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              'Add one here, or the first time you check out.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
