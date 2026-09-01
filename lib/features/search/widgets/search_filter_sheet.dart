import 'package:flutter/material.dart';

import '../../catalog/data/catalog_repository.dart' show Category;
import '../data/search_filters.dart';

/// The filter drawer for the results page.
///
/// Edits a copy and returns it on Apply, so dismissing the sheet cannot leave
/// half-made choices applied behind it.
///
/// Every control here that can be pressed changes the request. There is no size
/// or colour section, and the footnote says why rather than leaving a shopper
/// scrolling for one: the catalogue does not publish those fields, and the
/// endpoint accepts a `size=` parameter with a 200 and ignores it -- so such a
/// control would look like it worked and silently return the same rows.
///
/// **Rating and Brand are the two exceptions, and both are shown switched
/// off.** The reasoning and the measurements are on `kRatingTiers` and
/// `kBrandUnavailable`. They are here rather than absent so that a shopper
/// looking for one is told why it cannot be used, instead of hunting for a
/// control that was never going to appear.
///
/// The box at the top searches **these controls**, not the catalogue. Ninety-odd
/// options across six sections is more than anyone should have to scroll, and
/// the sub-category list is otherwise unreachable without knowing which of
/// forty-eight departments its parent is. Product searching stays in the header
/// bar behind this sheet, and the two never touch.
class SearchFilterSheet extends StatefulWidget {
  const SearchFilterSheet({
    super.key,
    required this.initial,
    this.departments = const [],
    this.brands = const [],
  });

  final SearchFilters initial;

  /// The shop's brand names, for the switched-off Brand section. Empty when the
  /// call has not answered or had nothing to say, in which case the section is
  /// simply not drawn -- it is inert either way.
  final List<String> brands;

  /// Top-level departments, with their children. Empty while the tree is still
  /// loading, in which case those two sections are simply not offered.
  final List<Category> departments;

  @override
  State<SearchFilterSheet> createState() => _SearchFilterSheetState();
}

class _SearchFilterSheetState extends State<SearchFilterSheet> {
  late SearchFilters _draft = widget.initial;

  /// What is typed into the box at the top of the sheet.
  ///
  /// **Local state, and deliberately not a field on [SearchFilters].** That
  /// class's rule is that everything on it is something the server honours;
  /// this changes no request at all. It decides which controls are drawn and
  /// nothing else -- it is a way of finding a filter among ninety-odd of them,
  /// not a filter.
  ///
  /// It is also emphatically **not** the product search. That lives in the
  /// header bar behind this sheet and still updates the grid as it is typed
  /// into; the two never touch.
  late final _search = TextEditingController();

  String _find = '';

  /// Whether a control's label matches what is being looked for.
  ///
  /// Case-insensitive substring. Not fuzzy and not prefix-only: someone typing
  /// "phone" should find "Mobile phone accessories", and a shopper hunting a
  /// control does not know which word of its name comes first.
  bool _matches(String label) =>
      _find.isEmpty || label.toLowerCase().contains(_find);

  /// Whether a whole section is drawn.
  ///
  /// Three ways in: nothing is being looked for, the section's own heading
  /// matches, or one of its options does. Plus [holds] -- **a section that
  /// holds a selection is always shown**, whatever is typed. Hiding a filter
  /// that is actively narrowing the results is how somebody ends up with a
  /// short list and nothing on screen explaining why.
  bool _section(String heading, {bool holds = false, bool anyOption = false}) =>
      _find.isEmpty || holds || _matches(heading) || anyOption;

  /// The options of one section that survive the current search.
  ///
  /// Matching options first; a selected option always survives, because hiding
  /// one that is narrowing the results is the one thing this box must never do.
  /// **Only when nothing at all matched** does a matching heading bring the
  /// whole section back -- typing "price" should show every band.
  ///
  /// That order matters, and the bug it fixes is worth naming: letting the
  /// heading match override the option filter meant typing "men" kept every
  /// department, because *"Depart**men**t"* contains it. A heading is a way of
  /// asking for a section, not a wildcard over its contents.
  List<T> _options<T>(
    String heading,
    List<T> all,
    String Function(T) label, {
    bool Function(T)? selected,
  }) {
    if (_find.isEmpty) return all;
    final hits = [
      for (final option in all)
        if (_matches(label(option)) || (selected?.call(option) ?? false))
          option,
    ];
    if (hits.isNotEmpty) return hits;
    return _matches(heading) ? all : <T>[];
  }

  List<Category> get _shownDepartments => _options(
    'Department',
    widget.departments,
    (department) => department.name,
    selected: (department) => _draft.departmentCid == department.cid,
  );

  bool get _showDepartments =>
      widget.departments.isNotEmpty && _shownDepartments.isNotEmpty;

  List<PriceBand> get _shownBands => _options(
    'Price',
    PriceBand.values,
    (band) => band.label,
    selected: _draft.bands.contains,
  );

  bool get _showPrice => _section(
    'Price',
    holds: _draft.bands.isNotEmpty || _draft.hasCustomRange,
    anyOption: _shownBands.isNotEmpty,
  );

  List<String> get _shownBrands =>
      _options('Brand', widget.brands, (brand) => brand);

  bool get _showBrand =>
      _section('Brand', anyOption: _shownBrands.isNotEmpty) &&
      // Nothing to say when the call failed or answered empty: the section is
      // inert either way, and a heading over one sentence and no chips is
      // noise rather than information.
      widget.brands.isNotEmpty;

  /// Labelled "4+ stars" for matching although the chip reads "4+": a shopper
  /// looking for this control types "star", not a plus sign.
  List<int> get _shownTiers =>
      _options('Rating', kRatingTiers, (tier) => '$tier+ stars');

  bool get _showRating =>
      _section('Rating', anyOption: _shownTiers.isNotEmpty) &&
      _shownTiers.isNotEmpty;

  bool get _showAvailability => _section(
    'Availability',
    holds: _draft.pricedOnly,
    anyOption: _matches('Priced items only') || _matches('In stock'),
  );

  /// True when the box has been typed into and nothing at all matched.
  bool get _nothingMatched =>
      _find.isNotEmpty &&
      !_showDepartments &&
      _matchingChildren.isEmpty &&
      !_showPrice &&
      !_showRating &&
      !_showBrand &&
      !_showAvailability;

  /// Every subcategory in the tree whose name matches, with its department.
  ///
  /// The reason the box is worth having. The Category section otherwise shows
  /// nothing until a department is picked, so reaching "Capacitor" means already
  /// knowing it lives under Electronic components. The whole tree is in memory,
  /// so this costs no request.
  List<({Category child, Category parent})> get _matchingChildren {
    if (_find.isEmpty) return const [];
    return [
      for (final department in widget.departments)
        for (final child in department.children)
          if (_matches(child.name)) (child: child, parent: department),
    ];
  }

  late final _min = TextEditingController(
    text: _asText(widget.initial.customMin),
  );
  late final _max = TextEditingController(
    text: _asText(widget.initial.customMax),
  );

  static String _asText(num? value) {
    if (value == null) return '';
    return value == value.roundToDouble() ? '${value.round()}' : '$value';
  }

  @override
  void dispose() {
    _search.dispose();
    _min.dispose();
    _max.dispose();
    super.dispose();
  }

  /// Reads both boxes into the draft.
  ///
  /// Parsing is deliberately forgiving and the model does the rest: a box that
  /// will not parse is the same as an empty one -- no bound -- rather than an
  /// error message over a half-typed number. Someone midway through typing
  /// "1200" has passed through "1", "12" and "120", and none of those is a
  /// mistake worth interrupting them about.
  void _readRange() {
    setState(() {
      _draft = _draft.withCustomRange(
        min: num.tryParse(_min.text.trim()),
        max: num.tryParse(_max.text.trim()),
      );
    });
  }

  /// Subcategories of whatever department is chosen. Empty when none is, which
  /// is why the category section asks for a department first rather than
  /// listing eleven hundred subcategories with no parent.
  List<Category> get _subcategories {
    final cid = _draft.departmentCid;
    if (cid == null) return const [];
    for (final department in widget.departments) {
      if (department.cid == cid) return department.children;
    }
    return const [];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 16, 4),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'Close',
                  onPressed: () => Navigator.of(context).pop(),
                ),
                Expanded(
                  child: Text(
                    'Filters',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (_draft.count > 0)
                  Text(
                    '${_draft.count} selected',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Flexible(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 12),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: TextField(
                    controller: _search,
                    textInputAction: TextInputAction.search,
                    // Narrows the controls below as it is typed. It never
                    // reaches the server: this searches the filters, not the
                    // catalogue.
                    onChanged: (value) =>
                        setState(() => _find = value.trim().toLowerCase()),
                    decoration: InputDecoration(
                      hintText: 'Find a filter',
                      helperText: 'Searches the filters below, not products',
                      prefixIcon: const Icon(Icons.search),
                      isDense: true,
                      suffixIcon: _find.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.clear),
                              tooltip: 'Clear',
                              onPressed: () {
                                _search.clear();
                                setState(() => _find = '');
                              },
                            ),
                    ),
                  ),
                ),
                if (_showDepartments) ...[
                  const _Heading('Department'),
                  _ChipWrap(
                    children: [
                      for (final department in _shownDepartments)
                        FilterChip(
                          label: Text(department.name),
                          selected: _draft.departmentCid == department.cid,
                          onSelected: (selected) => setState(() {
                            _draft = _draft.withDepartment(
                              selected ? department.cid : null,
                              selected ? department.name : null,
                            );
                          }),
                        ),
                    ],
                  ),
                ],
                if (widget.departments.isNotEmpty) ...[
                  // Searching reaches the whole tree, so a subcategory can be
                  // picked without its department being found first. Each chip
                  // says which department it sits in, because "Accessories"
                  // appears under half a dozen of them and the name alone does
                  // not say which one this is.
                  if (_find.isNotEmpty && _matchingChildren.isNotEmpty) ...[
                    const _Heading('Category'),
                    _ChipWrap(
                      children: [
                        for (final match in _matchingChildren)
                          FilterChip(
                            label: Text(match.child.name),
                            avatar: const Icon(Icons.subdirectory_arrow_right),
                            tooltip: 'in ${match.parent.name}',
                            selected: _draft.categoryCid == match.child.cid,
                            onSelected: (selected) => setState(() {
                              if (!selected) {
                                _draft = _draft.withCategory(null, null);
                                return;
                              }
                              // Both, in this order. withDepartment clears any
                              // category under the old department, so setting
                              // the parent first leaves a coherent pair of
                              // chips rather than a subcategory hanging under
                              // a department nobody chose.
                              _draft = _draft
                                  .withDepartment(
                                    match.parent.cid,
                                    match.parent.name,
                                  )
                                  .withCategory(
                                    match.child.cid,
                                    match.child.name,
                                  );
                            }),
                          ),
                      ],
                    ),
                  ] else if (_find.isEmpty && _subcategories.isNotEmpty) ...[
                    const _Heading('Category'),
                    _ChipWrap(
                      children: [
                        for (final category in _subcategories)
                          FilterChip(
                            label: Text(category.name),
                            selected: _draft.categoryCid == category.cid,
                            onSelected: (selected) => setState(() {
                              _draft = _draft.withCategory(
                                selected ? category.cid : null,
                                selected ? category.name : null,
                              );
                            }),
                          ),
                      ],
                    ),
                  ] else if (_find.isEmpty && _draft.departmentCid == null) ...[
                    const _Heading('Category'),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                      child: Text(
                        'Pick a department to narrow it further.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ],
                if (_showPrice) ...[
                  const _Heading('Price'),
                  _ChipWrap(
                    children: [
                      for (final band in _shownBands)
                        FilterChip(
                          label: Text(band.label),
                          selected: _draft.bands.contains(band),
                          onSelected: (selected) => setState(() {
                            final bands = {..._draft.bands};
                            if (selected) {
                              bands.add(band);
                            } else {
                              bands.remove(band);
                            }
                            _draft = _draft.withBands(bands);
                            // withBands drops any typed range, so the boxes are
                            // emptied to match. Leaving numbers sitting in them
                            // that no longer affect anything is the one thing
                            // that would make the two controls look like they
                            // disagree.
                            _min.clear();
                            _max.clear();
                          }),
                        ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _min,
                            keyboardType: TextInputType.number,
                            onChanged: (_) => _readRange(),
                            decoration: const InputDecoration(
                              labelText: 'Min',
                              prefixText: 'Rs. ',
                              isDense: true,
                            ),
                          ),
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 10),
                          child: Text('to'),
                        ),
                        Expanded(
                          child: TextField(
                            controller: _max,
                            keyboardType: TextInputType.number,
                            onChanged: (_) => _readRange(),
                            decoration: const InputDecoration(
                              labelText: 'Max',
                              prefixText: 'Rs. ',
                              isDense: true,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                    child: Text(
                      'Leave either box empty for no limit.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
                if (_showBrand) ...[
                  const _Heading('Brand'),
                  _ChipWrap(
                    children: [
                      for (final brand in _shownBrands)
                        FilterChip(
                          label: Text(brand),
                          selected: false,
                          // Disabled, like the rating tiers and for the same
                          // kind of reason -- see kBrandUnavailable. The names
                          // are the shop's own, from GET /brands, rather than a
                          // plausible list typed into the app.
                          onSelected: null,
                        ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Text(
                      kBrandUnavailable,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
                if (_showRating) ...[
                  const _Heading('Rating'),
                  _ChipWrap(
                    children: [
                      for (final stars in _shownTiers)
                        FilterChip(
                          avatar: const Icon(Icons.star_outline, size: 16),
                          label: Text('$stars+'),
                          selected: false,
                          // Null, so the chip renders disabled. See kRatingTiers:
                          // every row in this catalogue has a null rating and the
                          // endpoint ignores min_rating, so a working control here
                          // would empty the grid whichever tier was picked.
                          onSelected: null,
                        ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Text(
                      kRatingUnavailable,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
                if (_showAvailability) ...[
                  const _Heading('Availability'),
                  SwitchListTile(
                    value: _draft.pricedOnly,
                    onChanged: (value) =>
                        setState(() => _draft = _draft.withPricedOnly(value)),
                    title: const Text('Priced items only'),
                    subtitle: const Text(
                      'Hides listings the catalogue has not priced yet',
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                  ),
                ],
                if (_nothingMatched)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
                    child: Text(
                      'No filter matches "${_search.text.trim()}".',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                // Hidden while the box is in use: it is a note about the whole
                // sheet, and under a search that has narrowed it to one section
                // it reads as a remark about that section.
                if (_find.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.info_outline,
                          size: 14,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            kUnsupportedFacets,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _draft.isEmpty
                        ? null
                        : () => setState(() {
                            _draft = _draft.cleared;
                            // The boxes are cleared with the draft. The search
                            // box is not: `cleared` keeps the query on purpose,
                            // because these words are what the shopper came to
                            // look for rather than a chip they asked to drop.
                            _min.clear();
                            _max.clear();
                          }),
                    child: const Text('Clear all'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(_draft),
                    // No count promised. Only the server knows how many rows
                    // match, and a number worked out from the page on screen
                    // would be a guess dressed as a fact.
                    child: const Text('Show results'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        label,
        style: Theme.of(context).textTheme.titleSmall
            ?.copyWith(fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _ChipWrap extends StatelessWidget {
  const _ChipWrap({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Wrap(spacing: 8, runSpacing: 8, children: children),
    );
  }
}
