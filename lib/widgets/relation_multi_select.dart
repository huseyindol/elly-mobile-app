import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/crud_payload.dart';
import 'state_views.dart';

/// Form field for relation id lists (componentIds, widgetIds, bannerIds, ...): options come
/// from a list endpoint, selected ones are chips, "Seç" opens a searchable checkbox sheet.
/// Controlled: the parent owns [selectedIds] and updates it in [onChanged].
class RelationMultiSelect extends StatefulWidget {
  final ApiService api;
  final String label;

  /// Options source relative to `/api/v1`, e.g. `/components/list` (plain list or page).
  final String endpoint;
  final String valueKey;

  /// Dot-path; `a|b` = first non-empty wins (see [resolveListText]).
  final String labelKey;

  final List<Object> selectedIds;
  final ValueChanged<List<Object>> onChanged;

  const RelationMultiSelect({
    super.key,
    required this.api,
    required this.label,
    required this.endpoint,
    required this.selectedIds,
    required this.onChanged,
    this.valueKey = 'id',
    this.labelKey = 'title|name',
  });

  @override
  State<RelationMultiSelect> createState() => _RelationMultiSelectState();
}

class _RelationMultiSelectState extends State<RelationMultiSelect> {
  List<Map<String, dynamic>>? _options;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final items = extractItems(await widget.api.get(widget.endpoint));
      if (mounted) setState(() => _options = items);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  String _labelOf(Object id) {
    final option = _options?.where((o) => o[widget.valueKey] == id).firstOrNull;
    return (option == null ? null : resolveListText(option, widget.labelKey)) ?? '#$id';
  }

  Future<void> _pick() async {
    final result = await showModalBottomSheet<List<Object>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1C1C22),
      builder: (_) => _RelationPickerSheet(
        title: widget.label,
        options: [
          for (final o in _options!)
            if (o[widget.valueKey] != null)
              MapEntry(o[widget.valueKey] as Object, resolveListText(o, widget.labelKey) ?? '#${o[widget.valueKey]}'),
        ],
        selected: widget.selectedIds,
      ),
    );
    if (result != null) widget.onChanged(result);
  }

  @override
  Widget build(BuildContext context) {
    final Widget trailing;
    if (_error != null) {
      trailing = IconButton(
        tooltip: '${widget.label} yüklenemedi, tekrar dene',
        icon: const Icon(Icons.refresh_rounded, color: Colors.redAccent),
        onPressed: _load,
      );
    } else if (_options == null) {
      trailing = SizedBox.square(dimension: 24, child: LoadingView(label: '${widget.label} yükleniyor'));
    } else {
      trailing = TextButton.icon(
        key: ValueKey('relation_pick_${widget.label}'),
        onPressed: _pick,
        icon: const Icon(Icons.checklist_rounded),
        label: const Text('Seç'),
      );
    }

    return InputDecorator(
      decoration: InputDecoration(
        labelText: widget.label,
        errorText: _error,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
      ),
      child: Row(
        children: [
          Expanded(
            child: widget.selectedIds.isEmpty
                ? Text('Seçili kayıt yok', style: TextStyle(color: Colors.white.withValues(alpha: 0.5)))
                : Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final id in widget.selectedIds)
                        InputChip(
                          key: ValueKey('relation_chip_$id'),
                          label: Text(_labelOf(id)),
                          onDeleted: () => widget.onChanged([...widget.selectedIds]..remove(id)),
                          deleteButtonTooltipMessage: 'Kaldır',
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
  final List<MapEntry<Object, String>> options;
  final List<Object> selected;

  const _RelationPickerSheet({required this.title, required this.options, required this.selected});

  @override
  State<_RelationPickerSheet> createState() => _RelationPickerSheetState();
}

class _RelationPickerSheetState extends State<_RelationPickerSheet> {
  late final Set<Object> _checked = {...widget.selected};
  String _query = '';

  List<Object> _result() => [
    ...widget.selected.where(_checked.contains),
    for (final o in widget.options)
      if (_checked.contains(o.key) && !widget.selected.contains(o.key)) o.key,
  ];

  @override
  Widget build(BuildContext context) {
    final visible = _query.isEmpty
        ? widget.options
        : widget.options.where((o) => o.value.toLowerCase().contains(_query)).toList();
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
                  onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
                  decoration: const InputDecoration(hintText: 'Ara', prefixIcon: Icon(Icons.search_rounded)),
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
