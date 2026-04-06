// Elly Mobile App — ComponentCard component
// Displays a single UI component entry with type badge, status badge, and description.

import { View, Text, TouchableOpacity, StyleSheet } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { Badge } from './Badge';
import { formatBooleanStatus } from '../../utils/formatStatus';
import type { ComponentItem, ComponentType } from '../../types/component';

interface ComponentCardProps {
  component: ComponentItem;
  onPress: () => void;
}

function getTypeBadgeVariant(type: ComponentType): 'info' | 'warning' | 'success' {
  if (type === 'BANNER') return 'info';
  if (type === 'WIDGET') return 'warning';
  return 'success';
}

export function ComponentCard({ component, onPress }: ComponentCardProps) {
  const status = formatBooleanStatus(component.status);

  return (
    <TouchableOpacity style={styles.card} onPress={onPress} activeOpacity={0.7}>
      <View style={styles.row}>
        <View style={styles.icon}>
          <Ionicons name="cube-outline" size={20} color="#7C3AED" />
        </View>
        <View style={styles.info}>
          <Text style={styles.name} numberOfLines={1}>{component.name}</Text>
          {component.description ? (
            <Text style={styles.desc} numberOfLines={1}>{component.description}</Text>
          ) : null}
          <View style={styles.badges}>
            <Badge label={component.type} variant={getTypeBadgeVariant(component.type)} />
            <Badge label={status.label} variant={status.variant} />
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
    backgroundColor: '#F5F3FF',
    justifyContent: 'center',
    alignItems: 'center',
  },
  info: { flex: 1 },
  name: { fontSize: 14, fontWeight: '600', color: '#111827', marginBottom: 2 },
  desc: { fontSize: 12, color: '#9CA3AF', marginBottom: 6 },
  badges: { flexDirection: 'row', gap: 6 },
});
