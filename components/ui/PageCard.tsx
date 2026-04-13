// Elly Mobile App — PageCard component
// Displays a single CMS page row: title, slug, optional description, status badge, and chevron.

import { View, Text, TouchableOpacity, StyleSheet } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { Badge } from './Badge';
import { SwipeableListItem } from './SwipeableListItem';
import { useThemeColor } from '../../hooks/useThemeColor';
import { formatBooleanStatus } from '../../utils/formatStatus';
import type { PageItem } from '../../types/page';

interface PageCardProps {
  page: PageItem;
  onPress: () => void;
  onDelete?: () => void;
}

export function PageCard({ page, onPress, onDelete }: PageCardProps) {
  const { colors } = useThemeColor();

  const status = formatBooleanStatus(page.status);

  return (
    <SwipeableListItem onView={onPress} onDelete={onDelete || (() => {})}>
      <TouchableOpacity
        style={[styles.card, { backgroundColor: colors.surface }]}
        onPress={onPress}
        activeOpacity={0.7}
      >
        <View style={styles.row}>
          <View style={styles.info}>
            <Text style={[styles.title, { color: colors.text }]} numberOfLines={1}>
              {page.title}
            </Text>
            <Text style={[styles.slug, { color: colors.textSubtle }]} numberOfLines={1}>
              /{page.slug}
            </Text>
            {page.description ? (
              <Text style={[styles.desc, { color: colors.textSubtle }]} numberOfLines={2}>
                {page.description}
              </Text>
            ) : null}
          </View>
          <View style={styles.right}>
            <Badge label={status.label} variant={status.variant} />
            <Ionicons name="chevron-forward" size={16} color="#D1D5DB" style={styles.chevron} />
          </View>
        </View>
      </TouchableOpacity>
    </SwipeableListItem>
  );
}

const styles = StyleSheet.create({
  card: {
    backgroundColor: '#fff',
    padding: 16,
  },
  row: { flexDirection: 'row', alignItems: 'flex-start' },
  info: { flex: 1, marginRight: 12 },
  title: { fontSize: 15, fontWeight: '600', color: '#111827', marginBottom: 2 },
  slug: { fontSize: 12, color: '#6B7280', fontFamily: 'monospace', marginBottom: 4 },
  desc: { fontSize: 13, color: '#9CA3AF', lineHeight: 18 },
  right: { alignItems: 'flex-end', gap: 8 },
  chevron: { marginTop: 4 },
});
