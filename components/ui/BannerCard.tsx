// Elly Mobile App — BannerCard component
// Displays a single banner with image preview, folder, status badge, and order index.

import { View, Text, TouchableOpacity, Image, StyleSheet } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { Badge } from './Badge';
import { SwipeableListItem } from './SwipeableListItem';
import { useThemeColor } from '../../hooks/useThemeColor';
import { formatBooleanStatus } from '../../utils/formatStatus';
import type { BannerItem } from '../../types/banner';

interface BannerCardProps {
  banner: BannerItem;
  onPress: () => void;
  onDelete?: () => void;
}

export function BannerCard({ banner, onPress, onDelete }: BannerCardProps) {
  const { colors } = useThemeColor();

  const status = formatBooleanStatus(banner.status);
  const imageUrl = banner.images?.mobile ?? banner.images?.tablet ?? banner.images?.desktop;

  return (
    <SwipeableListItem onView={onPress} onDelete={onDelete || (() => {})}>
      <TouchableOpacity
        style={[styles.card, { backgroundColor: colors.surface }]}
        onPress={onPress}
        activeOpacity={0.7}
      >
        <View style={styles.row}>
          {/* Image preview */}
          <View style={styles.imagePlaceholder}>
            {imageUrl ? (
              <Image source={{ uri: imageUrl }} style={styles.image} resizeMode="cover" />
            ) : (
              <Ionicons name="image-outline" size={24} color="#D1D5DB" />
            )}
          </View>
          {/* Info */}
          <View style={styles.info}>
            <Text style={[styles.title, { color: colors.text }]} numberOfLines={1}>
              {banner.title}
            </Text>
            {banner.altText ? (
              <Text style={styles.alt} numberOfLines={1}>
                {banner.altText}
              </Text>
            ) : null}
            {banner.subFolder ? (
              <View style={styles.folderRow}>
                <Ionicons name="folder-outline" size={12} color="#9CA3AF" />
                <Text style={styles.folder}>{banner.subFolder}</Text>
              </View>
            ) : null}
            <View style={styles.meta}>
              <Badge label={status.label} variant={status.variant} />
              <Text style={[styles.order, { color: colors.textSubtle }]}>#{banner.orderIndex}</Text>
            </View>
          </View>
          <Ionicons name="chevron-forward" size={16} color="#D1D5DB" style={styles.chevron} />
        </View>
      </TouchableOpacity>
    </SwipeableListItem>
  );
}

const styles = StyleSheet.create({
  card: {
    backgroundColor: '#fff',
    padding: 12,
  },
  row: { flexDirection: 'row', alignItems: 'center' },
  imagePlaceholder: {
    width: 64,
    height: 64,
    borderRadius: 8,
    backgroundColor: '#F3F4F6',
    justifyContent: 'center',
    alignItems: 'center',
    marginRight: 12,
    overflow: 'hidden',
  },
  image: { width: 64, height: 64 },
  info: { flex: 1 },
  title: { fontSize: 14, fontWeight: '600', color: '#111827', marginBottom: 2 },
  alt: { fontSize: 12, color: '#9CA3AF', marginBottom: 4 },
  folderRow: { flexDirection: 'row', alignItems: 'center', gap: 4, marginBottom: 4 },
  folder: { fontSize: 11, color: '#9CA3AF' },
  meta: { flexDirection: 'row', alignItems: 'center', gap: 8 },
  order: { fontSize: 11, color: '#9CA3AF' },
  chevron: { marginLeft: 8 },
});
