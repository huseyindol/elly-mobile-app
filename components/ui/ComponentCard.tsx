// Elly Mobile App — ComponentCard component
// Displays a single UI component entry with type badge, status badge, and description.

import { View, Text, TouchableOpacity, StyleSheet } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { Badge } from './Badge';
import { SwipeableListItem } from './SwipeableListItem';
import { useThemeColor } from '../../hooks/useThemeColor';
import { formatBooleanStatus } from '../../utils/formatStatus';
import { getTypeColor } from '../../utils/colorUtils';
import type { ComponentItem } from '../../types/component';

interface ComponentCardProps {
  component: ComponentItem;
  onPress: () => void;
  onDelete?: () => void;
}

export function ComponentCard({ component, onPress, onDelete }: ComponentCardProps) {
  const { colors } = useThemeColor();

  const status = formatBooleanStatus(component.status);

  return (
    <SwipeableListItem onView={onPress} onDelete={onDelete || (() => {})}>
      <TouchableOpacity
        style={[styles.card, { backgroundColor: colors.surface }]}
        onPress={onPress}
        activeOpacity={0.7}
      >
        <View style={styles.row}>
          <View style={styles.icon}>
            <Ionicons name="cube-outline" size={20} color="#7C3AED" />
          </View>
          <View style={styles.info}>
            <Text style={[styles.name, { color: colors.text }]} numberOfLines={1}>
              {component.name}
            </Text>
            {component.description ? (
              <Text style={[styles.desc, { color: colors.textSubtle }]} numberOfLines={1}>
                {component.description}
              </Text>
            ) : null}
            <View style={styles.badges}>
              <Text style={[styles.typeText, { color: getTypeColor(component.type) }]}>
                {component.type}
              </Text>
              <Badge label={status.label} variant={status.variant} />
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
    backgroundColor: '#F5F3FF',
    justifyContent: 'center',
    alignItems: 'center',
  },
  info: { flex: 1 },
  name: { fontSize: 14, fontWeight: '600', color: '#111827', marginBottom: 2 },
  desc: { fontSize: 12, color: '#9CA3AF', marginBottom: 6 },
  badges: { flexDirection: 'row', alignItems: 'center', gap: 8 },
  typeText: { fontSize: 11, fontWeight: '700' },
});
