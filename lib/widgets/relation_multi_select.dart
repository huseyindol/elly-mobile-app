import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/crud_payload.dart';
import '../services/text_format.dart';
import 'state_views.dart';

/// Form field for relation id lists (componentIds, widgetIds, bannerIds, ...): options come from a
/// list endpoint, the selection shows as chips (first [maxChips] + "+K daha"), "Seç" opens a
/// searchable checkbox sheet. Works with `Form` validate / save / reset like any FormField.
///
/// Paged sources: with [paged] every page is fetched up front (not lazily in the sheet), so chips of
/// already selected ids always have labels even when they are not on the first page.
/// shortcut: fine for relation sources of up to a few thousand rows ([_maxPages] × [_pageSize]);
/// for bigger sets switch the sheet to SearchablePagedList + a by-id label lookup.
class RelationMultiSelect extends FormField<List<Object>> {
  RelationMultiSelect({
    super.key,
    required ApiService api,
    required String label,

    /// Options source relative to `/api/v1`, e.g. `/components/list` or `/posts/list/paged`.
    required String endpoint,
    bool paged = false,
    String valueKey = 'id',

    /// Dot-path; `a|b` = first non-empty wins (see [resolveListText]).
    String labelKey = 'title|name',

    /// Optional second line in the picker (e.g. banner `subFolder`, component `type`); searchable too.
    String? subtitleKey,
    int maxChips = 6,
    bool isRequired = false,
    List<Object> initialValue = const [],
    ValueChanged<List<Object>>? onChanged,
    FormFieldValidator<List<Object>>? validator,
    super.onSaved,
    super.enabled,
    super.autovalidateMode,
  }) : super(
         initialValue: initialValue,
         validator: (value) {
           if (isRequired && (value == null || value.isEmpty)) return 'En az bir $label seçin';
           return validator?.call(value);
         },
         builder: (field) => _RelationInput(
           field: field,
           api: api,
           label: label,
           endpoint: endpoint,
           paged: paged,
           valueKey: valueKey,
           labelKey: labelKey,
           subtitleKey: subtitleKey,
           maxChips: maxChips,
           onChanged: onChanged,
         ),
       );
}

const _pageSize = 100;
const _maxPages = 50;

class _RelationInput extends StatefulWidget {
  final FormFieldState<List<Object>> field;
  final ApiService api;
  final String label;
  final String endpoint;
  final bool paged;
  final String valueKey;
  final String labelKey;
  final String? subtitleKey;
  final int maxChips;
  final ValueChanged<List<Object>>? onChanged;

  const _RelationInput({
    required this.field,
    required this.api,
    required this.label,
    required this.endpoint,
    required this.paged,
    required this.valueKey,
    required this.labelKey,
    required this.subtitleKey,
    required this.maxChips,
    required this.onChanged,
  });

  @override
  State<_RelationInput> createState() => _RelationInputState();
}

class _RelationInputState extends State<_RelationInput> {
  /// id → label, in endpoint order (Dart maps keep insertion order).
  Map<Object, String>? _options;
  Map<Object, String> _subtitles = const {};
  String? _error;
  int _generation = 0; // ignores a load superseded by an endpoint change

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_RelationInput old) {
    super.didUpdateWidget(old);
    if (old.endpoint != widget.endpoint ||
        old.paged != widget.paged ||
        old.valueKey != widget.valueKey ||
        old.labelKey != widget.labelKey ||
        old.subtitleKey != widget.subtitleKey) {
      _load();
    }
  }

  Future<List<Map<String, dynamic>>> _fetchAll() async {
    if (!widget.paged) return extractItems(await widget.api.get(widget.endpoint));
    final items = <Map<String, dynamic>>[];
    for (var page = 0; page < _maxPages; page++) {
      final data = await widget.api.get(pagedEndpoint(widget.endpoint, page, _pageSize));
      items.addAll(extractItems(data));
      if (isLastPage(data, _pageSize)) break;
    }
    return items;
  }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() {
      _options = null;
      _error = null;
    });
    try {
      final items = await _fetchAll();
      if (!mounted || generation != _generation) return;
      setState(() {
        _options = {
          for (final o in items)
            if (o[widget.valueKey] != null)
              o[widget.valueKey] as Object: resolveListText(o, widget.labelKey) ?? '#${o[widget.valueKey]}',
        };
        final subtitleKey = widget.subtitleKey;
        _subtitles = subtitleKey == null
            ? const {}
            : {
                for (final o in items)
                  if (o[widget.valueKey] != null && resolveListText(o, subtitleKey) != null)
                    o[widget.valueKey] as Object: resolveListText(o, subtitleKey)!,
              };
      });
    } catch (e) {
      if (mounted && generation == _generation) setState(() => _error = e.toString());
    }
  }

  List<Object> get _selected => widget.field.value ?? const [];

  void _set(List<Object> ids) {
    widget.field.didChange(ids);
    widget.onChanged?.call(ids);
  }

  Future<void> _pick() async {
    final result = await showModalBottomSheet<List<Object>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (_) =>
          _RelationPickerSheet(title: widget.label, options: _options!, subtitles: _subtitles, selected: _selected),
    );
    if (result != null) _set(result);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.field.widget.enabled;
    final scheme = Theme.of(context).colorScheme;
    final Widget trailing;
    if (_error != null) {
      trailing = IconButton(
        tooltip: '${widget.label} yüklenemedi, tekrar dene',
        icon: Icon(Icons.refresh_rounded, color: scheme.onErrorContainer),
        onPressed: _load,
      );
    } else if (_options == null) {
      trailing = SizedBox.square(dimension: 24, child: LoadingView(label: '${widget.label} yükleniyor'));
    } else {
      trailing = TextButton.icon(
        key: ValueKey('relation_pick_${widget.label}'),
        onPressed: enabled ? _pick : null,
        icon: const Icon(Icons.checklist_rounded),
        label: const Text('Seç'),
      );
    }

    final selected = _selected;
    final hidden = selected.length - widget.maxChips;
    return InputDecorator(
      decoration: InputDecoration(
        labelText: widget.label,
        errorText: widget.field.errorText ?? _error,
        enabled: enabled,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
      ),
      child: Row(
        children: [
          Expanded(
            child: selected.isEmpty
                ? Text('Seçili kayıt yok', style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.6)))
                : Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final id in selected.take(widget.maxChips))
                        InputChip(
                          key: ValueKey('relation_chip_$id'),
                          label: Text(_options?[id] ?? '#$id'),
                          onDeleted: enabled ? () => _set([...selected]..remove(id)) : null,
                          deleteButtonTooltipMessage: 'Kaldır',
                        ),
                      if (hidden > 0)
                        ActionChip(
                          key: const ValueKey('relation_more_chip'),
                          label: Text('+$hidden daha'),
                          tooltip: 'Tüm seçimleri göster',
                          onPressed: enabled && _options != null ? _pick : null,
                        ),
                    ],
                  ),
          ),
          trailing,
        ],
      ),
    );
  }
}

/// Returns the new selection: previously selected order kept, new picks appended in list order.
class _RelationPickerSheet extends StatefulWidget {
  final String title;
  final Map<Object, String> options;
  final Map<Object, String> subtitles;
  final List<Object> selected;

  const _RelationPickerSheet({
    required this.title,
    required this.options,
    required this.subtitles,
    required this.selected,
  });

  @override
  State<_RelationPickerSheet> createState() => _RelationPickerSheetState();
}

class _RelationPickerSheetState extends State<_RelationPickerSheet> {
  late final Set<Object> _checked = {...widget.selected};
  late final Set<Object> _initial = {...widget.selected};
  String _query = ''; // foldTr'd

  List<Object> _result() => [
    ...widget.selected.where(_checked.contains),
    for (final id in widget.options.keys)
      if (_checked.contains(id) && !_initial.contains(id)) id,
  ];

  @override
  Widget build(BuildContext context) {
    final visible = _query.isEmpty
        ? widget.options.entries.toList()
        : widget.options.entries
              .where((o) => foldTr('${o.value} ${widget.subtitles[o.key] ?? ''}').contains(_query))
              .toList();
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.75,
          child: Column(
            children: [
              ListTile(
                title: Text(widget.title, style: const TextStyle(fontWeight: FontWeight.bold)),
                trailing: FilledButton(
                  key: const ValueKey('relation_done_button'),
                  onPressed: () => Navigator.of(context).pop(_result()),
                  child: Text('Tamam (${_checked.length})'),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  key: const ValueKey('relation_search_field'),
                  onChanged: (v) => setState(() => _query = foldTr(v.trim())),
                  decoration: const InputDecoration(labelText: 'Ara', prefixIcon: Icon(Icons.search_rounded)),
                ),
              ),
              Expanded(
                child: visible.isEmpty
                    ? const EmptyView(message: 'Kayıt bulunamadı.')
                    : ListView.builder(
                        itemCount: visible.length,
                        itemBuilder: (context, i) {
                          final option = visible[i];
                          return CheckboxListTile(
                            key: ValueKey('relation_option_${option.key}'),
                            value: _checked.contains(option.key),
                            title: Text(option.value),
                            subtitle: widget.subtitles[option.key] == null ? null : Text(widget.subtitles[option.key]!),
                            onChanged: (on) =>
                                setState(() => on == true ? _checked.add(option.key) : _checked.remove(option.key)),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
