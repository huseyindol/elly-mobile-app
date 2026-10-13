import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill/quill_delta.dart';

import '../services/api_service.dart';
import '../services/rich_text_codec.dart';
import 'asset_picker.dart';

/// HTML body editor (posts `content`): Quill editor over the Tiptap subset elly-admin writes
/// ([analyzeHtml]). Bodies outside that subset (table, iframe, styled spans, …) open in raw HTML mode
/// with a warning, so saving never drops markup. Untouched bodies are saved byte-for-byte.
///
/// Read the value to save with `GlobalKey<RichTextFieldState>().currentState!.html`.
class RichTextField extends StatefulWidget {
  final String label;
  final String initialHtml;
  final ApiService api;

  /// Show "Assetlerden seç" in the image dialog (`assets:read`).
  final bool canPickAssets;

  /// Called on every edit (rich or raw), e.g. to mark the form dirty.
  final VoidCallback? onChanged;

  const RichTextField({
    super.key,
    required this.label,
    required this.initialHtml,
    required this.api,
    this.canPickAssets = false,
    this.onChanged,
  });

  @override
  State<RichTextField> createState() => RichTextFieldState();
}

class RichTextFieldState extends State<RichTextField> {
  final _raw = TextEditingController();
  QuillController? _quill; // null = raw HTML mode
  StreamSubscription<DocChange>? _changes;
  String _loadedHtml = '';
  bool _dirty = false;

  /// Why the body could not be opened in the editor (raw mode was forced).
  String? _problem;

  bool get isRawMode => _quill == null;

  /// The value to save differs from the initial body.
  bool get isDirty => html != widget.initialHtml;

  /// HTML to save. Rich mode: the loaded HTML as-is until the document changes.
  String get html {
    final quill = _quill;
    if (quill == null) return _raw.text;
    if (!_dirty) return _loadedHtml;
    return opsToHtml([for (final op in quill.document.toDelta().toJson()) Map<String, dynamic>.from(op)]);
  }

  @override
  void initState() {
    super.initState();
    final analysis = analyzeHtml(widget.initialHtml);
    if (analysis.supported) {
      _openRich(analysis.ops!, widget.initialHtml);
    } else {
      _raw.text = widget.initialHtml;
      _problem = analysis.problem;
    }
    _raw.addListener(() => widget.onChanged?.call());
  }

  void _openRich(List<Map<String, dynamic>> ops, String html) {
    _closeRich();
    final quill = QuillController(
      document: Document.fromJson(ops),
      selection: const TextSelection.collapsed(offset: 0),
      // Pasted HTML/Markdown could bring formatting the site's editor doesn't have (plain text paste only).
      // ignore: experimental_member_use
      config: const QuillControllerConfig(clipboardConfig: QuillClipboardConfig(enableExternalRichPaste: false)),
    );
    _changes = quill.document.changes.listen((_) {
      _dirty = true;
      widget.onChanged?.call();
    });
    _quill = quill;
    _loadedHtml = html;
    _dirty = false;
  }

  void _closeRich() {
    _changes?.cancel();
    _quill?.dispose();
    _quill = null;
  }

  @override
  void dispose() {
    _closeRich();
    _raw.dispose();
    super.dispose();
  }

  void _toggleMode() {
    if (!isRawMode) {
      setState(() {
        _raw.text = html;
        _closeRich();
        _problem = null;
      });
      return;
    }
    final analysis = analyzeHtml(_raw.text);
    if (!analysis.supported) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Editörde açılamaz: ${analysis.problem}. Ham HTML olarak kalıyor.'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }
    setState(() {
      _openRich(analysis.ops!, _raw.text);
      _problem = null;
    });
  }

  Future<void> _insertImage() async {
    final quill = _quill;
    if (quill == null) return;
    final image = await showDialog<({String url, String alt})>(
      context: context,
      builder: (_) => _ImageDialog(api: widget.api, canPickAssets: widget.canPickAssets),
    );
    if (image == null || !mounted) return;
    final doc = quill.document;
    var index = quill.selection.start < 0 ? doc.length - 1 : quill.selection.start;
    final length = quill.selection.end < 0 ? 0 : quill.selection.end - index;
    if (length > 0) quill.replaceText(index, length, '', null);
    // A block embed must sit alone on its line (opsToHtml writes images only for such lines): split the
    // current line around the caret. replaceText keeps the block style of the split halves.
    if (index > 0 && doc.toPlainText()[index - 1] != '\n') {
      quill.replaceText(index, 0, '\n', null);
      index++;
    }
    if (doc.toPlainText()[index] != '\n') quill.replaceText(index, 0, '\n', null);
    // compose (not replaceText + formatText): the alt travels on the embed op itself; formatText drops
    // attributes outside Quill's registry.
    quill.compose(
      Delta()
        ..retain(index)
        ..insert(BlockEmbed.image(image.url).toJson(), image.alt.isEmpty ? null : {'alt': image.alt}),
      TextSelection.collapsed(offset: index + 1),
      ChangeSource.local,
    );
    quill.updateSelection(TextSelection.collapsed(offset: index + 1), ChangeSource.local);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final quill = _quill;
    final border = Border.all(color: scheme.onSurface.withValues(alpha: 0.1));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Semantics(
                header: true,
                child: Text(widget.label, style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.7))),
              ),
            ),
            Tooltip(
              message: isRawMode ? 'Görsel editöre geç' : 'Ham HTML düzenlemeye geç',
              child: TextButton.icon(
                key: const ValueKey('rich_text_mode_button'),
                onPressed: _toggleMode,
                icon: Icon(isRawMode ? Icons.text_format_rounded : Icons.code_rounded),
                label: Text(isRawMode ? 'Editör' : 'HTML'),
              ),
            ),
          ],
        ),
        if (_problem != null)
          Container(
            key: const ValueKey('rich_text_warning'),
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: scheme.errorContainer, borderRadius: BorderRadius.circular(12)),
            child: Text(
              'Bu içerik mobil editörün desteklemediği HTML içeriyor ($_problem). Veri kaybını önlemek için '
              'ham HTML olarak düzenleniyor.',
              style: TextStyle(color: scheme.onErrorContainer),
            ),
          ),
        if (quill == null)
          TextField(
            key: const ValueKey('rich_text_raw'),
            controller: _raw,
            minLines: 8,
            maxLines: 30,
            keyboardType: TextInputType.multiline,
            style: const TextStyle(fontFamily: 'Courier', fontSize: 13),
            decoration: InputDecoration(
              labelText: '${widget.label} (HTML)',
              hintText: '<p>...</p>',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
            ),
          )
        else
          Container(
            decoration: BoxDecoration(border: border, borderRadius: BorderRadius.circular(16)),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                QuillSimpleToolbar(
                  controller: quill,
                  config: QuillSimpleToolbarConfig(
                    multiRowsDisplay: false,
                    showFontFamily: false,
                    showFontSize: false,
                    showColorButton: false,
                    showBackgroundColorButton: false,
                    showListCheck: false,
                    showSearchButton: false,
                    showSubscript: false,
                    showSuperscript: false,
                    // ≥40 dp touch targets on phones.
                    iconTheme: const QuillIconTheme(
                      iconButtonUnselectedData: IconButtonData(constraints: _minButton),
                      iconButtonSelectedData: IconButtonData(constraints: _minButton),
                    ),
                    buttonOptions: QuillSimpleToolbarButtonOptions(
                      selectHeaderStyleDropdownButton: const QuillToolbarSelectHeaderStyleDropdownButtonOptions(
                        attributes: [Attribute.header, Attribute.h1, Attribute.h2, Attribute.h3],
                      ),
                      // Site renders post HTML unsanitized: only http(s)/mailto/tel/relative links.
                      linkStyle: QuillToolbarLinkStyleButtonOptions(
                        validateLink: (link) => isAllowedUrl(link, link: true),
                      ),
                    ),
                    customButtons: [
                      QuillToolbarCustomButtonOptions(
                        icon: const Icon(Icons.image_outlined),
                        tooltip: 'Görsel ekle',
                        onPressed: _insertImage,
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, color: scheme.onSurface.withValues(alpha: 0.1)),
                QuillEditor.basic(
                  controller: quill,
                  config: const QuillEditorConfig(
                    scrollable: false,
                    minHeight: 200,
                    padding: EdgeInsets.all(12),
                    placeholder: 'İçerik yazın...',
                    embedBuilders: [_ImageEmbedBuilder(), _DividerEmbedBuilder()],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

const _minButton = BoxConstraints(minWidth: 40, minHeight: 40);

class _ImageEmbedBuilder extends EmbedBuilder {
  const _ImageEmbedBuilder();

  @override
  String get key => BlockEmbed.imageType;

  @override
  Widget build(BuildContext context, EmbedContext embedContext) {
    final src = embedContext.node.value.data.toString();
    final alt = embedContext.node.style.attributes['alt']?.value?.toString();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(
          ApiService.fileUrl(src),
          semanticLabel: alt,
          errorBuilder: (_, _, _) => ListTile(leading: const Icon(Icons.broken_image_outlined), title: Text(src)),
        ),
      ),
    );
  }
}

class _DividerEmbedBuilder extends EmbedBuilder {
  const _DividerEmbedBuilder();

  @override
  String get key => 'divider';

  @override
  Widget build(BuildContext context, EmbedContext embedContext) => const Divider(height: 24);
}

class _ImageDialog extends StatefulWidget {
  final ApiService api;
  final bool canPickAssets;
  const _ImageDialog({required this.api, required this.canPickAssets});

  @override
  State<_ImageDialog> createState() => _ImageDialogState();
}

class _ImageDialogState extends State<_ImageDialog> {
  final _url = TextEditingController();
  final _alt = TextEditingController();

  @override
  void dispose() {
    _url.dispose();
    _alt.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final url = await showAssetPicker(context, widget.api);
    if (url != null) setState(() => _url.text = url);
  }

  @override
  Widget build(BuildContext context) {
    final url = _url.text.trim();
    final valid = isAllowedUrl(url);
    return AlertDialog(
      scrollable: true,
      title: const Text('Görsel ekle'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const ValueKey('rich_image_url'),
            controller: _url,
            keyboardType: TextInputType.url,
            decoration: InputDecoration(
              labelText: 'Görsel URL',
              hintText: 'https://...',
              errorText: url.isEmpty || valid ? null : 'Yalnız http(s) ya da göreli adres',
            ),
            onChanged: (_) => setState(() {}),
          ),
          TextField(
            key: const ValueKey('rich_image_alt'),
            controller: _alt,
            decoration: const InputDecoration(labelText: 'Alternatif metin (alt)'),
          ),
          if (widget.canPickAssets)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _pick,
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text('Assetlerden seç'),
              ),
            ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('İptal')),
        FilledButton(
          key: const ValueKey('rich_image_insert'),
          onPressed: !valid ? null : () => Navigator.of(context).pop((url: url, alt: _alt.text.trim())),
          child: const Text('Ekle'),
        ),
      ],
    );
  }
}
