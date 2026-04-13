// Elly Mobile App — StatusToggle component
// Boolean active/inactive toggle switch with label and status text.

import { View, Text, TouchableOpacity, StyleSheet } from 'react-native';
import { Ionicons } from '@expo/vector-icons';

interface StatusToggleProps {
  value: boolean;
  onChange: (value: boolean) => void;
  label?: string;
}

export function StatusToggle({ value, onChange, label = 'Durum' }: StatusToggleProps) {
  return (
    <View style={styles.row}>
      <View style={styles.labelRow}>
        <Ionicons
          name={value ? 'checkmark-circle' : 'ellipse-outline'}
          size={20}
          color={value ? '#059669' : '#D1D5DB'}
        />
        <Text style={styles.label}>{label}</Text>
      </View>
      <TouchableOpacity
        style={[styles.toggle, value && styles.toggleActive]}
        onPress={() => onChange(!value)}
        activeOpacity={0.8}
      >
        <View style={[styles.thumb, value && styles.thumbActive]} />
      </TouchableOpacity>
      <Text style={[styles.status, value && styles.statusActive]}>{value ? 'Aktif' : 'Pasif'}</Text>
    </View>
  );
}

const styles = StyleSheet.create({
  row: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
    paddingVertical: 4,
  },
  labelRow: {
    flex: 1,
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
  },
  label: {
    fontSize: 14,
    fontWeight: '500',
    color: '#374151',
  },
  toggle: {
    width: 48,
    height: 28,
    borderRadius: 14,
    backgroundColor: '#E5E7EB',
    padding: 2,
    justifyContent: 'center',
  },
  toggleActive: {
    backgroundColor: '#4F46E5',
  },
  thumb: {
    width: 24,
    height: 24,
    borderRadius: 12,
    backgroundColor: '#fff',
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 1 },
    shadowOpacity: 0.2,
    shadowRadius: 2,
    elevation: 2,
  },
  thumbActive: {
    transform: [{ translateX: 20 }],
  },
  status: {
    fontSize: 13,
    color: '#9CA3AF',
    fontWeight: '500',
    minWidth: 40,
  },
  statusActive: {
    color: '#059669',
  },
});
