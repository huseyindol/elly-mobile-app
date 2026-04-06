// Elly Mobile App — AssetCard component
// Displays a single asset in a grid tile: image preview or file-type icon, name, extension, and optional subFolder.

import { View, Text, TouchableOpacity, Image, StyleSheet } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import type { AssetItem } from '../../types/asset';

interface AssetCardProps {
  asset: AssetItem;
  onPress: () => void;
}

function getFileIcon(mimeType: string): keyof typeof Ionicons.glyphMap {
  if (mimeType.startsWith('image/')) return 'image-outline';
  if (mimeType.startsWith('video/')) return 'videocam-outline';
  if (mimeType.includes('pdf')) return 'document-outline';
  if (mimeType.includes('zip') || mimeType.includes('archive')) return 'archive-outline';
  return 'document-attach-outline';
}

export function AssetCard({ asset, onPress }: AssetCardProps) {
  const isImage = asset.type.startsWith('image/');

  return (
    <TouchableOpacity style={styles.card} onPress={onPress} activeOpacity={0.7}>
      <View style={styles.preview}>
        {isImage ? (
          <Image source={{ uri: asset.path }} style={styles.image} resizeMode="cover" />
        ) : (
          <Ionicons name={getFileIcon(asset.type)} size={28} color="#6B7280" />
        )}
      </View>
      <View style={styles.info}>
        <Text style={styles.name} numberOfLines={2}>{asset.name}</Text>
        <Text style={styles.ext}>.{asset.extension}</Text>
        {asset.subFolder && (
          <View style={styles.folderRow}>
            <Ionicons name="folder-outline" size={11} color="#9CA3AF" />
            <Text style={styles.folder}>{asset.subFolder}</Text>
          </View>
        )}
      </View>
    </TouchableOpacity>
  );
}

const styles = StyleSheet.create({
  card: { backgroundColor: '#fff', borderRadius: 12, overflow: 'hidden', width: '48%', marginBottom: 12, shadowColor: '#000', shadowOffset: { width: 0, height: 1 }, shadowOpacity: 0.06, shadowRadius: 4, elevation: 2 },
  preview: { width: '100%', height: 100, backgroundColor: '#F3F4F6', justifyContent: 'center', alignItems: 'center' },
  image: { width: '100%', height: 100 },
  info: { padding: 8 },
  name: { fontSize: 12, fontWeight: '600', color: '#111827', marginBottom: 2 },
  ext: { fontSize: 11, color: '#9CA3AF', marginBottom: 2 },
  folderRow: { flexDirection: 'row', alignItems: 'center', gap: 3 },
  folder: { fontSize: 10, color: '#9CA3AF' },
});
