import 'package:flutter/material.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import '../services/api_service.dart';
import '../services/rich_text_codec.dart';

enum PreviewViewport { mobile, desktop }

class PostPreviewData {
  final String title;
  final String slug;
  final String content;
  final String description;
  final String category;
  final String coverImage;
  final String publishedAt;
  final String author;
  final String readingTime;

  const PostPreviewData({
    this.title = '',
    this.slug = '',
    this.content = '',
    this.description = '',
    this.category = '',
    this.coverImage = '',
    this.publishedAt = '',
    this.author = '',
    this.readingTime = '',
  });
}

Future<void> showPostPreviewSheet(
  BuildContext context, {
  required PostPreviewData post,
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Önizlemeyi kapat',
    barrierColor: Colors.black87,
    pageBuilder: (ctx, _, _) => PostPreviewSheet(post: post),
  );
}

class PostPreviewSheet extends StatefulWidget {
  final PostPreviewData post;

  const PostPreviewSheet({super.key, required this.post});

  @override
  State<PostPreviewSheet> createState() => _PostPreviewSheetState();
}

class _PostPreviewSheetState extends State<PostPreviewSheet> {
  PreviewViewport _viewport = PreviewViewport.mobile;
  bool _previewDark = true;
  bool _themeInitialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_themeInitialized) {
      _previewDark = Theme.of(context).brightness == Brightness.dark;
      _themeInitialized = true;
    }
  }

  static const _turkishMonths = [
    'Ocak',
    'Şubat',
    'Mart',
    'Nisan',
    'Mayıs',
    'Haziran',
    'Temmuz',
    'Ağustos',
    'Eylül',
    'Ekim',
    'Kasım',
    'Aralık',
  ];

  static String formatTurkishDate(String raw) {
    final trimmed = raw.trim();
    final parsed = trimmed.isEmpty ? DateTime.now() : (DateTime.tryParse(trimmed) ?? DateTime.now());
    return '${parsed.day} ${_turkishMonths[parsed.month - 1]} ${parsed.year}';
  }

  static String estimateReadingTime(String readingTime, String htmlContent) {
    final trimmed = readingTime.trim();
    if (trimmed.isNotEmpty) {
      final lower = trimmed.toLowerCase();
      if (lower.contains('okuma')) return trimmed;
      if (lower.contains('dk')) return '$trimmed okuma';
      return '$trimmed dk okuma';
    }
    final plain = html_parser.parseFragment(htmlContent).text?.replaceAll(RegExp(r'\s+'), ' ').trim() ?? '';
    if (plain.isEmpty) return '1 dk okuma';
    final words = plain.split(' ').length;
    final mins = (words / 200).ceil().clamp(1, 999);
    return '$mins dk okuma';
  }

  (Color bg, Color fg) _categoryColors(String category, bool dark) {
    switch (category.trim()) {
      case 'Frontend':
        return dark
            ? (const Color(0x4D1E3A8A), const Color(0xFF93C5FD))
            : (const Color(0xFFDBEAFE), const Color(0xFF1D4ED8));
      case 'Backend':
        return dark
            ? (const Color(0x4D064E3B), const Color(0xFF6EE7B7))
            : (const Color(0xFFD1FAE5), const Color(0xFF047857));
      case 'DevOps':
        return dark
            ? (const Color(0x4D7C2D12), const Color(0xFFFDBA74))
            : (const Color(0xFFFFEDD5), const Color(0xFFC2410C));
      case 'AI':
      case 'Yapay Zeka':
        return dark
            ? (const Color(0x4D4C1D95), const Color(0xFFC4B5FD))
            : (const Color(0xFFEDE9FE), const Color(0xFF6D28D9));
      case 'Mobile':
      case 'Mobil':
        return dark
            ? (const Color(0x4D831843), const Color(0xFFF9A8D4))
            : (const Color(0xFFFCE7F3), const Color(0xFFBE185D));
      default:
        return dark
            ? (const Color(0xFF1E293B), const Color(0xFFCBD5E1))
            : (const Color(0xFFF1F5F9), const Color(0xFF334155));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = _viewport == PreviewViewport.mobile;
    final post = widget.post;
    final displayTitle = post.title.trim().isEmpty ? 'Başlıksız Makale' : post.title.trim();
    final displaySlug = post.slug.trim().isEmpty ? 'ornek-makale' : post.slug.trim();
    final displayAuthor = post.author.trim().isEmpty ? 'Hüseyin DOL' : post.author.trim();
    final displayCategory = post.category.trim();
    final displayDescription = post.description.trim();
    final rawCover = post.coverImage.trim();
    final hasValidCover = rawCover.isNotEmpty && isAllowedUrl(rawCover);
    final formattedDate = formatTurkishDate(post.publishedAt);
    final readingTimeLabel = estimateReadingTime(post.readingTime, post.content);

    final pageBg = _previewDark ? const Color(0xFF020617) : Colors.white;
    final primaryText = _previewDark ? Colors.white : const Color(0xFF0F172A);
    final mutedText = _previewDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    final borderColor = _previewDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0);

    return Scaffold(
      backgroundColor: const Color(0xFF090D16),
      body: SafeArea(
        child: Column(
          children: [
            // Control Header Bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: const BoxDecoration(
                color: Color(0xFF0F172A),
                border: Border(bottom: BorderSide(color: Color(0xFF1E293B))),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: Color(0xFF34D399),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Canlı Site Önizlemesi (elly-tenant)',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        key: const ValueKey('post_preview_theme_toggle'),
                        tooltip: _previewDark ? 'Açık site teması' : 'Koyu site teması',
                        onPressed: () => setState(() => _previewDark = !_previewDark),
                        icon: Icon(
                          _previewDark ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
                          color: _previewDark ? const Color(0xFFA78BFA) : const Color(0xFFFBBF24),
                          size: 20,
                        ),
                      ),
                      IconButton(
                        key: const ValueKey('post_preview_close'),
                        tooltip: 'Önizlemeyi kapat',
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close_rounded, color: Colors.white70, size: 22),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Viewport Switcher (Mobil Web vs Masaüstü)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _ViewportButton(
                        buttonKey: const ValueKey('post_preview_viewport_mobile'),
                        icon: Icons.smartphone_rounded,
                        label: 'Mobil Web (390px)',
                        selected: isMobile,
                        onTap: () => setState(() => _viewport = PreviewViewport.mobile),
                      ),
                      const SizedBox(width: 8),
                      _ViewportButton(
                        buttonKey: const ValueKey('post_preview_viewport_desktop'),
                        icon: Icons.desktop_windows_rounded,
                        label: 'Masaüstü (Desktop)',
                        selected: !isMobile,
                        onTap: () => setState(() => _viewport = PreviewViewport.desktop),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Scrollable Preview Stage
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                  horizontal: isMobile ? 12 : 16,
                  vertical: 16,
                ),
                child: Center(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final targetWidth = isMobile ? 390.0 : 920.0;
                      final frame = _buildBrowserFrame(
                        isMobile: isMobile,
                        targetWidth: targetWidth,
                        pageBg: pageBg,
                        primaryText: primaryText,
                        mutedText: mutedText,
                        borderColor: borderColor,
                        displayTitle: displayTitle,
                        displaySlug: displaySlug,
                        displayAuthor: displayAuthor,
                        displayCategory: displayCategory,
                        displayDescription: displayDescription,
                        hasValidCover: hasValidCover,
                        rawCover: rawCover,
                        formattedDate: formattedDate,
                        readingTimeLabel: readingTimeLabel,
                        htmlContent: post.content,
                      );

                      // When previewing Desktop on a narrower phone screen, scale the 920px desktop
                      // canvas down proportionally so the author sees the true desktop layout & proportions.
                      if (!isMobile && constraints.maxWidth < targetWidth) {
                        return FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.topCenter,
                          child: SizedBox(width: targetWidth, child: frame),
                        );
                      }
                      return ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: targetWidth),
                        child: frame,
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBrowserFrame({
    required bool isMobile,
    required double targetWidth,
    required Color pageBg,
    required Color primaryText,
    required Color mutedText,
    required Color borderColor,
    required String displayTitle,
    required String displaySlug,
    required String displayAuthor,
    required String displayCategory,
    required String displayDescription,
    required bool hasValidCover,
    required String rawCover,
    required String formattedDate,
    required String readingTimeLabel,
    required String htmlContent,
  }) {
    final (catBg, catFg) = _categoryColors(displayCategory, _previewDark);
    final contentPadding = isMobile
        ? const EdgeInsets.fromLTRB(20, 0, 20, 48)
        : const EdgeInsets.fromLTRB(64, 0, 64, 72);

    return Container(
      key: ValueKey('post_preview_frame_${_viewport.name}'),
      decoration: BoxDecoration(
        color: pageBg,
        borderRadius: BorderRadius.circular(isMobile ? 28 : 16),
        border: Border.all(
          color: const Color(0xFF1E293B),
          width: isMobile ? 5 : 1.5,
        ),
        boxShadow: const [
          BoxShadow(
            color: Colors.black54,
            blurRadius: 24,
            offset: Offset(0, 12),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Simulated Address Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: _previewDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
              border: Border(bottom: BorderSide(color: borderColor)),
            ),
            child: Row(
              children: [
                _dot(const Color(0xFFF43F5E)),
                const SizedBox(width: 5),
                _dot(const Color(0xFFF59E0B)),
                const SizedBox(width: 5),
                _dot(const Color(0xFF10B981)),
                const SizedBox(width: 10),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: _previewDark ? const Color(0xFF020617) : Colors.white,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'huseyindol.com/makaleler/$displaySlug',
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                        color: mutedText,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  isMobile ? '390px' : 'Desktop',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: mutedText,
                  ),
                ),
              ],
            ),
          ),

          // Cover Image Hero (matches elly-tenant /makaleler/[slug])
          if (hasValidCover)
            SizedBox(
              height: isMobile ? 210 : 340,
              width: double.infinity,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.network(
                    ApiService.fileUrl(rawCover),
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFF0F172A), Color(0xFF1E1B4B), Color(0xFF0F172A)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                    ),
                  ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          pageBg,
                          pageBg.withValues(alpha: 0.4),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            Container(
              height: 80,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF0F172A), Color(0xFF1E1B4B), Color(0xFF0F172A)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            ),

          // Article Container (max-w-3xl equivalent)
          Padding(
            padding: contentPadding,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(height: isMobile ? 20 : 28),
                    // Back link
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.arrow_back_rounded, size: 16, color: mutedText),
                        const SizedBox(width: 6),
                        Text(
                          'Makalelere Dön',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: mutedText,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: isMobile ? 20 : 28),

                    // Category Badge
                    if (displayCategory.isNotEmpty) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: catBg,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          displayCategory,
                          style: TextStyle(
                            color: catFg,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],

                    // Title (H1)
                    Text(
                      displayTitle,
                      style: TextStyle(
                        color: primaryText,
                        fontSize: isMobile ? 26 : 42,
                        fontWeight: FontWeight.w800,
                        height: 1.2,
                        letterSpacing: -0.5,
                      ),
                    ),

                    // Description
                    if (displayDescription.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      Text(
                        displayDescription,
                        style: TextStyle(
                          color: mutedText,
                          fontSize: isMobile ? 15 : 18,
                          height: 1.5,
                        ),
                      ),
                    ],

                    const SizedBox(height: 18),
                    Divider(color: borderColor, height: 1),
                    const SizedBox(height: 16),

                    // Meta Row: Author + Date + Reading Time
                    Wrap(
                      spacing: 18,
                      runSpacing: 10,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 32,
                              height: 32,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: _previewDark
                                    ? const Color(0xFF064E3B)
                                    : const Color(0xFFD1FAE5),
                                shape: BoxShape.circle,
                                border: Border.all(color: borderColor, width: 1.5),
                              ),
                              child: Text(
                                displayAuthor
                                    .substring(0, displayAuthor.length >= 2 ? 2 : 1)
                                    .toUpperCase(),
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: _previewDark
                                      ? const Color(0xFF6EE7B7)
                                      : const Color(0xFF047857),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              displayAuthor,
                              style: TextStyle(
                                color: primaryText,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.calendar_today_outlined, size: 14, color: mutedText),
                            const SizedBox(width: 6),
                            Text(
                              formattedDate,
                              style: TextStyle(color: mutedText, fontSize: 13),
                            ),
                          ],
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.schedule_rounded, size: 15, color: mutedText),
                            const SizedBox(width: 5),
                            Text(
                              readingTimeLabel,
                              style: TextStyle(color: mutedText, fontSize: 13),
                            ),
                          ],
                        ),
                      ],
                    ),

                    SizedBox(height: isMobile ? 24 : 36),

                    // HTML Article Body
                    _TenantHtmlRenderer(
                      html: htmlContent,
                      isDark: _previewDark,
                      isMobile: isMobile,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dot(Color color) => Container(
    width: 9,
    height: 9,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

class _ViewportButton extends StatelessWidget {
  final Key buttonKey;
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ViewportButton({
    required this.buttonKey,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? const Color(0xFF7C3AED) : const Color(0xFF1E293B),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        key: buttonKey,
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: Colors.white),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Renders HTML content using the exact typography & color palette of
/// `elly-tenant/src/components/html-content.tsx`.
class _TenantHtmlRenderer extends StatelessWidget {
  final String html;
  final bool isDark;
  final bool isMobile;

  const _TenantHtmlRenderer({
    required this.html,
    required this.isDark,
    required this.isMobile,
  });

  Color get _headingColor => isDark ? Colors.white : const Color(0xFF0F172A);
  Color get _bodyColor => isDark ? const Color(0xFFCBD5E1) : const Color(0xFF334155);
  Color get _borderColor => isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0);

  @override
  Widget build(BuildContext context) {
    final fragment = html_parser.parseFragment(html);
    final plain = fragment.text?.trim() ?? '';
    if (plain.isEmpty && fragment.querySelectorAll('img').isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _borderColor),
        ),
        child: Text(
          'Henüz makale içeriği girilmedi. İçerik alanına yazdığınız veya AI ile oluşturduğunuz metin burada gerçek site görünümüyle yer alacak.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
            fontSize: 13,
            height: 1.5,
          ),
        ),
      );
    }

    final blocks = _buildBlocks(fragment.nodes);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: blocks,
    );
  }

  List<Widget> _buildBlocks(dom.NodeList nodes) {
    final widgets = <Widget>[];
    for (final node in nodes) {
      if (node is dom.Text) {
        final t = node.text.trim();
        if (t.isNotEmpty) {
          widgets.add(_paragraphFromSpans([TextSpan(text: t)]));
        }
        continue;
      }
      if (node is! dom.Element) continue;
      final tag = node.localName?.toLowerCase() ?? '';
      switch (tag) {
        case 'h1':
          widgets.add(
            Padding(
              padding: const EdgeInsets.only(top: 24, bottom: 12),
              child: Text.rich(
                TextSpan(
                  style: TextStyle(
                    color: _headingColor,
                    fontSize: isMobile ? 24 : 32,
                    fontWeight: FontWeight.w800,
                    height: 1.25,
                  ),
                  children: _inlineSpans(node.nodes),
                ),
              ),
            ),
          );
        case 'h2':
          widgets.add(
            Padding(
              padding: const EdgeInsets.only(top: 22, bottom: 10),
              child: Text.rich(
                TextSpan(
                  style: TextStyle(
                    color: _headingColor,
                    fontSize: isMobile ? 20 : 26,
                    fontWeight: FontWeight.w700,
                    height: 1.3,
                  ),
                  children: _inlineSpans(node.nodes),
                ),
              ),
            ),
          );
        case 'h3':
        case 'h4':
        case 'h5':
        case 'h6':
          widgets.add(
            Padding(
              padding: const EdgeInsets.only(top: 18, bottom: 8),
              child: Text.rich(
                TextSpan(
                  style: TextStyle(
                    color: _headingColor,
                    fontSize: isMobile ? 17 : 21,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                  children: _inlineSpans(node.nodes),
                ),
              ),
            ),
          );
        case 'p':
          final imgs = node.querySelectorAll('img');
          if (imgs.isNotEmpty && node.text.trim().isEmpty) {
            for (final img in imgs) {
              widgets.add(_buildImage(img));
            }
          } else {
            widgets.add(_paragraphFromSpans(_inlineSpans(node.nodes)));
          }
        case 'ul':
        case 'ol':
          widgets.add(_buildList(node, ordered: tag == 'ol'));
        case 'blockquote':
          widgets.add(
            Container(
              margin: const EdgeInsets.symmetric(vertical: 16),
              padding: const EdgeInsets.only(left: 16, top: 4, bottom: 4),
              decoration: const BoxDecoration(
                border: Border(
                  left: BorderSide(color: Color(0xFF10B981), width: 4),
                ),
              ),
              child: DefaultTextStyle.merge(
                style: TextStyle(
                  fontStyle: FontStyle.italic,
                  color: isDark ? const Color(0xFFE2E8F0) : const Color(0xFF1E293B),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: _buildBlocks(node.nodes),
                ),
              ),
            ),
          );
        case 'pre':
          widgets.add(
            Container(
              width: double.infinity,
              margin: const EdgeInsets.symmetric(vertical: 16),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF020617),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _borderColor),
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Text(
                  node.text.trimRight(),
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 13,
                    color: Color(0xFFF1F5F9),
                    height: 1.5,
                  ),
                ),
              ),
            ),
          );
        case 'img':
          widgets.add(_buildImage(node));
        case 'hr':
          widgets.add(
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Divider(color: _borderColor, height: 1),
            ),
          );
        default:
          widgets.addAll(_buildBlocks(node.nodes));
      }
    }
    return widgets;
  }

  Widget _paragraphFromSpans(List<InlineSpan> spans) {
    if (spans.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Text.rich(
        TextSpan(
          style: TextStyle(
            color: _bodyColor,
            fontSize: isMobile ? 15.5 : 17.5,
            height: 1.65,
          ),
          children: spans,
        ),
      ),
    );
  }

  Widget _buildList(dom.Element listEl, {required bool ordered}) {
    final items = listEl.children.where((c) => c.localName?.toLowerCase() == 'li').toList();
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 16, left: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < items.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 24,
                    child: Text(
                      ordered ? '${i + 1}.' : '•',
                      style: TextStyle(
                        color: const Color(0xFF10B981),
                        fontWeight: FontWeight.w700,
                        fontSize: isMobile ? 15.5 : 17.5,
                        height: 1.6,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        style: TextStyle(
                          color: _bodyColor,
                          fontSize: isMobile ? 15.5 : 17.5,
                          height: 1.6,
                        ),
                        children: _inlineSpans(items[i].nodes),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildImage(dom.Element imgEl) {
    final src = imgEl.attributes['src']?.trim() ?? '';
    final alt = imgEl.attributes['alt']?.trim() ?? '';
    if (src.isEmpty || !isAllowedUrl(src)) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.network(
              ApiService.fileUrl(src),
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.image_outlined, color: _bodyColor),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        alt.isNotEmpty ? alt : src,
                        style: TextStyle(color: _bodyColor, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (alt.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                alt,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                  fontSize: 12,
                ),
              ),
            ),
        ],
      ),
    );
  }

  List<InlineSpan> _inlineSpans(dom.NodeList nodes, {TextStyle? inherited}) {
    final spans = <InlineSpan>[];
    for (final node in nodes) {
      if (node is dom.Text) {
        final text = node.text.replaceAll(RegExp(r'\s+'), ' ');
        if (text.isNotEmpty) {
          spans.add(TextSpan(text: text, style: inherited));
        }
        continue;
      }
      if (node is! dom.Element) continue;
      final tag = node.localName?.toLowerCase() ?? '';
      if (tag == 'br') {
        spans.add(const TextSpan(text: '\n'));
        continue;
      }
      TextStyle nextStyle = inherited ?? const TextStyle();
      switch (tag) {
        case 'strong':
        case 'b':
          nextStyle = nextStyle.copyWith(
            fontWeight: FontWeight.w700,
            color: _headingColor,
          );
        case 'em':
        case 'i':
          nextStyle = nextStyle.copyWith(fontStyle: FontStyle.italic);
        case 'u':
          nextStyle = nextStyle.copyWith(decoration: TextDecoration.underline);
        case 's':
        case 'del':
        case 'strike':
          nextStyle = nextStyle.copyWith(decoration: TextDecoration.lineThrough);
        case 'code':
          nextStyle = nextStyle.copyWith(
            fontFamily: 'monospace',
            fontSize: (isMobile ? 14 : 15),
            backgroundColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
            color: isDark ? const Color(0xFF34D399) : const Color(0xFF059669),
          );
        case 'a':
          nextStyle = nextStyle.copyWith(
            color: const Color(0xFF10B981),
            fontWeight: FontWeight.w600,
            decoration: TextDecoration.underline,
          );
      }
      spans.addAll(_inlineSpans(node.nodes, inherited: nextStyle));
    }
    return spans;
  }
}
