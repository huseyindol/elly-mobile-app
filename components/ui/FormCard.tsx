// Elly Mobile App — FormCard component
// Displays a single form schema row: icon, title, version, active/passive badge, and chevron.

import { View, Text, TouchableOpacity, StyleSheet } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { Badge } from './Badge';
import type { FormSchemaSummary } from '../../types/form';

interface FormCardProps {
  form: FormSchemaSummary;
  onPress: () => void;
}

export function FormCard({ form, onPress }: FormCardProps) {
  return (
    <TouchableOpacity style={styles.card} onPress={onPress} activeOpacity={0.7}>
      <View style={styles.row}>
        <View style={styles.icon}>
          <Ionicons name="list-outline" size={20} color="#4F46E5" />
        </View>
        <View style={styles.info}>
          <Text style={styles.title} numberOfLines={1}>{form.title}</Text>
          <Text style={styles.version}>v{form.version}</Text>
          <Badge label={form.active ? 'Aktif' : 'Pasif'} variant={form.active ? 'success' : 'neutral'} />
        </View>
        <Ionicons name="chevron-forward" size={16} color="#D1D5DB" />
      </View>
    </TouchableOpacity>
  );
}

const styles = StyleSheet.create({
  card: { backgroundColor: '#fff', borderRadius: 12, padding: 14, marginBottom: 10, shadowColor: '#000', shadowOffset: { width: 0, height: 1 }, shadowOpacity: 0.06, shadowRadius: 4, elevation: 2 },
  row: { flexDirection: 'row', alignItems: 'center', gap: 12 },
  icon: { width: 40, height: 40, borderRadius: 10, backgroundColor: '#EEF2FF', justifyContent: 'center', alignItems: 'center' },
  info: { flex: 1, gap: 4 },
  title: { fontSize: 14, fontWeight: '600', color: '#111827' },
  version: { fontSize: 12, color: '#9CA3AF' },
});
