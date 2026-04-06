// Elly Mobile App — WidgetCard component
// Displays a single widget entry with type badge, status badge, order index, and description.

import { View, Text, TouchableOpacity, StyleSheet } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { Badge } from './Badge';
import { formatBooleanStatus } from '../../utils/formatStatus';
import type { WidgetItem, WidgetType } from '../../types/widget';

interface WidgetCardProps {
  widget: WidgetItem;
  onPress: () => void;
}

export function WidgetCard({ widget, onPress }: WidgetCardProps) {
  const status = formatBooleanStatus(widget.status);
  const typeVariant: 'info' | 'warning' = widget.type === 'BANNER' ? 'info' : 'warning';

  return (
    <TouchableOpacity style={styles.card} onPress={onPress} activeOpacity={0.7}>
      <View style={styles.row}>
        <View style={styles.icon}>
          <Ionicons name="apps-outline" size={20} color="#DB2777" />
        </View>
        <View style={styles.info}>
          <Text style={styles.name} numberOfLines={1}>{widget.name}</Text>
          {widget.description ? (
            <Text style={styles.desc} numberOfLines={1}>{widget.description}</Text>
          ) : null}
          <View style={styles.badges}>
            <Badge label={widget.type} variant={typeVariant} />
            <Badge label={status.label} variant={status.variant} />
            <Text style={styles.order}>#{widget.orderIndex}</Text>
          </View>
        </View>
        <Ionicons name="chevron-forward" size={16} color="#D1D5DB" />
      </View>
    </TouchableOpacity>
  );
}

const styles = StyleSheet.create({
  card: {
    backgroundColor: '#fff',
    borderRadius: 12,
    padding: 14,
    marginBottom: 10,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 1 },
    shadowOpacity: 0.06,
    shadowRadius: 4,
    elevation: 2,
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
  badges: { flexDirection: 'row', alignItems: 'center', gap: 6 },
  order: { fontSize: 11, color: '#9CA3AF' },
});
