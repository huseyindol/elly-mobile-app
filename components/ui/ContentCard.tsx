// Elly Mobile App — ContentCard component
// Displays a single content item row: icon, title, sectionKey, contentType, active badge, sort order, and chevron.

import { View, Text, TouchableOpacity, StyleSheet } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { Badge } from './Badge';
import { SwipeableListItem } from './SwipeableListItem';
import { useThemeColor } from '../../hooks/useThemeColor';
import { getTypeColor } from '../../utils/colorUtils';
import type { ContentItem } from '../../types/content';

interface ContentCardProps {
  content: ContentItem;
  onPress: () => void;
  onDelete?: () => void;
}

export function ContentCard({ content, onPress, onDelete }: ContentCardProps) {
  const { colors } = useThemeColor();

  const { basicInfo, contentType } = content;
  return (
    <SwipeableListItem onView={onPress} onDelete={onDelete || (() => {})}>
      <TouchableOpacity
        style={[styles.card, { backgroundColor: colors.surface }]}
        onPress={onPress}
        activeOpacity={0.7}
      >
        <View style={styles.row}>
          <View style={styles.icon}>
            <Ionicons name="reader-outline" size={20} color="#059669" />
          </View>
          <View style={styles.info}>
            <Text style={[styles.title, { color: colors.text }]} numberOfLines={1}>
              {basicInfo?.title || 'İsimsiz İçerik'}
            </Text>
            <View style={styles.meta}>
              <Text style={[styles.section, { color: colors.textSubtle }]}>
                {basicInfo?.sectionKey || 'Tanımsız'}
              </Text>
              <Text style={styles.dot}>·</Text>
              <Text style={[styles.type, { color: getTypeColor(contentType), fontWeight: '700' }]}>
                {contentType}
              </Text>
            </View>
            <View style={styles.badges}>
              <Badge
                label={basicInfo?.isActive ? 'Aktif' : 'Pasif'}
                variant={basicInfo?.isActive ? 'success' : 'neutral'}
              />
              <Text style={styles.sort}>#{basicInfo?.sortOrder ?? 0}</Text>
            </View>
          </View>
          <Ionicons name="chevron-forward" size={16} color="#D1D5DB" />
        </View>
      </TouchableOpacity>
    </SwipeableListItem>
  );
}

const styles = StyleSheet.create({
  card: {
    backgroundColor: '#fff',
    padding: 14,
  },
  row: { flexDirection: 'row', alignItems: 'center', gap: 12 },
  icon: {
    width: 40,
    height: 40,
    borderRadius: 10,
    backgroundColor: '#ECFDF5',
    justifyContent: 'center',
    alignItems: 'center',
  },
  info: { flex: 1 },
  title: { fontSize: 14, fontWeight: '600', color: '#111827', marginBottom: 2 },
  meta: { flexDirection: 'row', alignItems: 'center', gap: 4, marginBottom: 4 },
  section: { fontSize: 12, color: '#6B7280' },
  dot: { color: '#D1D5DB' },
  type: { fontSize: 12, color: '#9CA3AF' },
  badges: { flexDirection: 'row', alignItems: 'center', gap: 6 },
  sort: { fontSize: 11, color: '#9CA3AF' },
});
