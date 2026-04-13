// Elly Mobile App — FormBuilderFieldList
// Renders the list of form fields in the form builder, with edit/delete actions.

import { View, Text, FlatList, TouchableOpacity, StyleSheet } from 'react-native';
import { useThemeColor } from '../../hooks/useThemeColor';
import { Ionicons } from '@expo/vector-icons';
import type { FormField } from '../../types/form';

const FIELD_TYPE_LABELS: Record<string, string> = {
  text: 'Metin',
  email: 'E-posta',
  number: 'Sayı',
  select: 'Açılır Liste',
  checkbox: 'Onay Kutusu',
  multi_checkbox: 'Çoklu Onay',
  radio: 'Radyo Buton',
  textarea: 'Metin Alanı',
  date: 'Tarih',
  phone: 'Telefon',
  url: 'URL',
};

interface FormBuilderFieldListProps {
  fields: FormField[];
  onEdit: (field: FormField) => void;
  onDelete: (fieldId: string) => void;
  onAdd: () => void;
}

export function FormBuilderFieldList({
  fields,
  onEdit,
  onDelete,
  onAdd,
}: FormBuilderFieldListProps) {
  const { colors, isDark } = useThemeColor();
  return (
    <View
      style={[
        styles.container,
        { backgroundColor: colors.surface, borderColor: isDark ? '#374151' : '#E5E7EB' },
      ]}
    >
      <View style={styles.header}>
        <Text style={[styles.title, { color: colors.text }]}>Alanlar ({fields.length})</Text>
        <TouchableOpacity style={styles.addBtn} onPress={onAdd}>
          <Ionicons name="add" size={18} color="#fff" />
          <Text style={styles.addBtnText}>Alan Ekle</Text>
        </TouchableOpacity>
      </View>

      {fields.length === 0 ? (
        <View style={styles.empty}>
          <Ionicons name="list-outline" size={32} color="#D1D5DB" />
          <Text style={styles.emptyText}>Henüz alan eklenmedi</Text>
          <TouchableOpacity style={styles.emptyAddBtn} onPress={onAdd}>
            <Text style={styles.emptyAddBtnText}>İlk Alanı Ekle</Text>
          </TouchableOpacity>
        </View>
      ) : (
        <FlatList
          data={fields}
          keyExtractor={(item) => item.id}
          scrollEnabled={false}
          renderItem={({ item, index }) => (
            <View style={[styles.fieldCard, { borderBottomColor: isDark ? '#374151' : '#F3F4F6' }]}>
              <View style={styles.fieldLeft}>
                <View style={styles.indexBadge}>
                  <Text style={styles.indexText}>{index + 1}</Text>
                </View>
                <View style={styles.fieldInfo}>
                  <Text style={[styles.fieldLabel, { color: colors.text }]}>{item.label}</Text>
                  <View style={styles.fieldMeta}>
                    <Text style={styles.fieldType}>
                      {FIELD_TYPE_LABELS[item.type] ?? item.type}
                    </Text>
                    {item.required && <Text style={styles.requiredBadge}>Zorunlu</Text>}
                  </View>
                </View>
              </View>
              <View style={styles.fieldActions}>
                <TouchableOpacity style={styles.actionBtn} onPress={() => onEdit(item)}>
                  <Ionicons name="pencil-outline" size={18} color="#4F46E5" />
                </TouchableOpacity>
                <TouchableOpacity style={styles.actionBtn} onPress={() => onDelete(item.id)}>
                  <Ionicons name="trash-outline" size={18} color="#EF4444" />
                </TouchableOpacity>
              </View>
            </View>
          )}
        />
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    backgroundColor: '#fff',
    borderRadius: 12,
    padding: 16,
    marginBottom: 16,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 1 },
    shadowOpacity: 0.05,
    shadowRadius: 4,
    elevation: 2,
  },
  header: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: 12,
  },
  title: { fontSize: 15, fontWeight: '600', color: '#111827' },
  addBtn: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 4,
    backgroundColor: '#4F46E5',
    paddingHorizontal: 12,
    paddingVertical: 6,
    borderRadius: 8,
  },
  addBtnText: { fontSize: 13, fontWeight: '600', color: '#fff' },
  empty: { alignItems: 'center', paddingVertical: 24, gap: 8 },
  emptyText: { fontSize: 14, color: '#9CA3AF' },
  emptyAddBtn: {
    marginTop: 4,
    paddingHorizontal: 16,
    paddingVertical: 8,
    borderRadius: 8,
    borderWidth: 1,
    borderColor: '#4F46E5',
  },
  emptyAddBtnText: { fontSize: 14, color: '#4F46E5', fontWeight: '500' },
  fieldCard: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingVertical: 10,
    borderBottomWidth: 1,
  },
  fieldLeft: { flexDirection: 'row', alignItems: 'center', flex: 1, gap: 10 },
  indexBadge: {
    width: 24,
    height: 24,
    borderRadius: 12,
    backgroundColor: '#EEF2FF',
    alignItems: 'center',
    justifyContent: 'center',
  },
  indexText: { fontSize: 11, fontWeight: '700', color: '#4F46E5' },
  fieldInfo: { flex: 1 },
  fieldLabel: { fontSize: 14, fontWeight: '500', color: '#111827' },
  fieldMeta: { flexDirection: 'row', gap: 6, marginTop: 2 },
  fieldType: { fontSize: 12, color: '#6B7280' },
  requiredBadge: {
    fontSize: 11,
    color: '#EF4444',
    fontWeight: '600',
    backgroundColor: '#FEF2F2',
    paddingHorizontal: 6,
    paddingVertical: 1,
    borderRadius: 4,
  },
  fieldActions: { flexDirection: 'row', gap: 4 },
  actionBtn: { padding: 6 },
});
