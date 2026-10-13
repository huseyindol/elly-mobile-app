import 'package:flutter/material.dart';

import '../services/api_service.dart';
import 'searchable_paged_list.dart';

const _imageExtensions = {'png', 'jpg', 'jpeg', 'gif', 'webp', 'svg', 'avif', 'bmp', 'ico'};

/// Asset row (`DtoAssets`) is an image: `type` image/* or a known image extension.
bool isImageAsset(Map<String, dynamic> asset) =>
    (asset['type']?.toString() ?? '').startsWith('image/') ||
    _imageExtensions.contains(asset['extension']?.toString().replaceFirst('.', '').toLowerCase());

/// Square image preview of a stored path or URL; broken/missing images show an icon.
class AssetThumbnail extends StatelessWidget {
  final String? url;
  final double size;
  final String? semanticLabel;

  const AssetThumbnail({super.key, required this.url, this.size = 48, this.semanticLabel});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final placeholder = Icon(Icons.image_not_supported_outlined, color: scheme.onSurface.withValues(alpha: 0.5));
    final value = url?.trim() ?? '';
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: size,
        height: size,
        color: scheme.onSurface.withValues(alpha: 0.06),
        child: value.isEmpty
            ? placeholder
            : Image.network(
                ApiService.fileUrl(value),
                fit: BoxFit.cover,
                semanticLabel: semanticLabel,
                errorBuilder: (_, _, _) => placeholder,
              ),
      ),
    );
  }
}

/// Bottom sheet listing image assets (`/assets/list/paged`, newest first); returns the picked
/// asset's absolute URL (works in HTML bodies and URL fields alike), null when dismissed.
Future<String?> showAssetPicker(BuildContext context, ApiService api) => showModalBottomSheet<String>(
  context: context,
  isScrollControlled: true,
  backgroundColor: Theme.of(context).colorScheme.surface,
  builder: (sheetContext) => SafeArea(
    child: SizedBox(
      height: MediaQuery.sizeOf(sheetContext).height * 0.8,
      child: Column(
        children: [
          ListTile(
            title: const Text('Assetlerden seç', style: TextStyle(fontWeight: FontWeight.bold)),
            trailing: IconButton(
              tooltip: 'Kapat',
              icon: const Icon(Icons.close_rounded),
              onPressed: () => Navigator.of(sheetContext).pop(),
            ),
          ),
          Expanded(
            child: SearchablePagedList(
              api: api,
              endpoint: '/assets/list/paged?sort=id,desc',
              paged: true,
              itemFilter: isImageAsset,
              searchText: (item) => '${item['name'] ?? ''} ${item['subFolder'] ?? ''}',
              emptyMessage: 'Görsel bulunamadı.',
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              itemBuilder: (context, item) => ListTile(
                key: ValueKey('asset_pick_${item['id']}'),
                leading: AssetThumbnail(url: item['path']?.toString()),
                title: Text(item['name']?.toString() ?? '#${item['id']}', overflow: TextOverflow.ellipsis),
                subtitle: Text(item['subFolder']?.toString() ?? ''),
                onTap: () => Navigator.of(sheetContext).pop(ApiService.fileUrl(item['path'].toString())),
              ),
            ),
          ),
        ],
      ),
    ),
  ),
);
