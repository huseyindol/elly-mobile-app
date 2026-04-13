// Elly Mobile App — WidgetCard component
// Displays a single widget entry with type badge, status badge, order index, and description.

import { View, Text, TouchableOpacity, StyleSheet } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { Badge } from './Badge';
import { SwipeableListItem } from './SwipeableListItem';
import { useThemeColor } from '../../hooks/useThemeColor';
import { formatBooleanStatus } from '../../utils/formatStatus';
import { getTypeColor } from '../../utils/colorUtils';
import type { WidgetItem } from '../../types/widget';

interface WidgetCardProps {
  widget: WidgetItem;
  onPress: () => void;
  onDelete?: () => void;
}

export function WidgetCard({ widget, onPress, onDelete }: WidgetCardProps) {
  const { colors } = useThemeColor();

  const status = formatBooleanStatus(widget.status);

  return (
    <SwipeableListItem onView={onPress} onDelete={onDelete || (() => {})}>
      <TouchableOpacity
        style={[styles.card, { backgroundColor: colors.surface }]}
        onPress={onPress}
        activeOpacity={0.7}
      >
        <View style={styles.row}>
          <View style={styles.icon}>
            <Ionicons name="apps-outline" size={20} color="#DB2777" />
          </View>
          <View style={styles.info}>
            <Text style={[styles.name, { color: colors.text }]} numberOfLines={1}>
              {widget.name}
            </Text>
            {widget.description ? (
              <Text style={[styles.desc, { color: colors.textSubtle }]} numberOfLines={1}>
                {widget.description}
              </Text>
            ) : null}
            <View style={styles.badges}>
              <Text style={[styles.typeText, { color: getTypeColor(widget.type) }]}>
                {widget.type}
              </Text>
              <Badge label={status.label} variant={status.variant} />
              <Text style={[styles.order, { color: colors.textSubtle }]}>#{widget.orderIndex}</Text>
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
    backgroundColor: '#FDF2F8',
    justifyContent: 'center',
    alignItems: 'center',
  },
  info: { flex: 1 },
  name: { fontSize: 14, fontWeight: '600', color: '#111827', marginBottom: 2 },
  desc: { fontSize: 12, color: '#9CA3AF', marginBottom: 6 },
  badges: { flexDirection: 'row', alignItems: 'center', gap: 8 },
  typeText: { fontSize: 11, fontWeight: '700' },
  order: { fontSize: 11, color: '#9CA3AF' },
});
