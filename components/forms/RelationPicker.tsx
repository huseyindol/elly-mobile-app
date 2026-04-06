// Elly Mobile App — RelationPicker
// Reusable multi-select picker displayed as a bottom-sheet Modal.
// Used for selecting banners, widgets, forms, or posts linked to components/widgets.

import { useState, useMemo } from 'react';
import {
  Modal, View, Text, FlatList, TouchableOpacity,
  TextInput, StyleSheet, KeyboardAvoidingView, Platform,
} from 'react-native';
import { Ionicons } from '@expo/vector-icons';

export interface RelationItem {
  id: number;
  label: string;
  sublabel?: string;
}

interface RelationPickerProps {
  label: string;
  items: RelationItem[];
  selectedIds: number[];
  onChange: (ids: number[]) => void;
  isLoading?: boolean;
}

export function RelationPicker({
  label,
  items,
  selectedIds,
  onChange,
  isLoading = false,
}: RelationPickerProps) {
  const [open, setOpen] = useState(false);
  const [search, setSearch] = useState('');

  const filtered = useMemo(
    () =>
      search.trim()
        ? items.filter((i) =>
            i.label.toLowerCase().includes(search.toLowerCase()),
          )
        : items,
    [items, search],
  );

  function toggle(id: number) {
    onChange(
      selectedIds.includes(id)
        ? selectedIds.filter((s) => s !== id)
        : [...selectedIds, id],
    );
  }

  const selectedLabels = items
    .filter((i) => selectedIds.includes(i.id))
    .map((i) => i.label);

  return (
    <View style={styles.wrapper}>
      <Text style={styles.label}>{label}</Text>

      <TouchableOpacity
        style={styles.trigger}
        onPress={() => setOpen(true)}
        disabled={isLoading}
      >
        <Text style={styles.triggerText} numberOfLines={2}>
          {isLoading
            ? 'Yükleniyor...'
            : selectedLabels.length === 0
            ? 'Seçmek için dokunun'
            : selectedLabels.join(', ')}
        </Text>
        <View style={styles.triggerRight}>
          {selectedLabels.length > 0 && (
            <View style={styles.badge}>
              <Text style={styles.badgeText}>{selectedLabels.length}</Text>
            </View>
          )}
          <Ionicons name="chevron-down" size={16} color="#6B7280" />
        </View>
      </TouchableOpacity>

      <Modal visible={open} animationType="slide" transparent onRequestClose={() => setOpen(false)}>
        <View style={styles.overlay}>
          <KeyboardAvoidingView behavior={Platform.OS === 'ios' ? 'padding' : undefined} style={styles.sheet}>
            <View style={styles.header}>
              <Text style={styles.headerTitle}>{label} Seç</Text>
              <TouchableOpacity onPress={() => setOpen(false)} hitSlop={{ top: 8, bottom: 8, left: 8, right: 8 }}>
                <Ionicons name="close" size={22} color="#374151" />
              </TouchableOpacity>
            </View>

            <View style={styles.searchRow}>
              <Ionicons name="search-outline" size={16} color="#9CA3AF" style={styles.searchIcon} />
              <TextInput
                style={styles.searchInput}
                value={search}
                onChangeText={setSearch}
                placeholder="Ara..."
                placeholderTextColor="#9CA3AF"
              />
            </View>

            <FlatList
              data={filtered}
              keyExtractor={(item) => String(item.id)}
              style={styles.list}
              renderItem={({ item }) => {
                const selected = selectedIds.includes(item.id);
                return (
                  <TouchableOpacity style={styles.row} onPress={() => toggle(item.id)}>
                    <View style={styles.rowInfo}>
                      <Text style={styles.rowLabel}>{item.label}</Text>
                      {item.sublabel && (
                        <Text style={styles.rowSublabel}>{item.sublabel}</Text>
                      )}
                    </View>
                    <View style={[styles.check, selected && styles.checkSelected]}>
                      {selected && <Ionicons name="checkmark" size={14} color="#fff" />}
                    </View>
                  </TouchableOpacity>
                );
              }}
              ListEmptyComponent={
                <View style={styles.empty}>
                  <Text style={styles.emptyText}>Sonuç bulunamadı</Text>
                </View>
              }
            />

            <View style={styles.footer}>
              <TouchableOpacity style={styles.clearBtn} onPress={() => onChange([])}>
                <Text style={styles.clearBtnText}>Temizle</Text>
              </TouchableOpacity>
              <TouchableOpacity style={styles.doneBtn} onPress={() => setOpen(false)}>
                <Text style={styles.doneBtnText}>Tamam ({selectedIds.length})</Text>
              </TouchableOpacity>
            </View>
          </KeyboardAvoidingView>
        </View>
      </Modal>
    </View>
  );
}

const styles = StyleSheet.create({
  wrapper: { marginBottom: 12 },
  label: { fontSize: 14, fontWeight: '500', color: '#374151', marginBottom: 6 },
  trigger: {
    flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between',
    borderWidth: 1, borderColor: '#D1D5DB', borderRadius: 10,
    paddingHorizontal: 12, paddingVertical: 10, backgroundColor: '#FAFAFA',
  },
  triggerText: { fontSize: 14, color: '#374151', flex: 1, marginRight: 8 },
  triggerRight: { flexDirection: 'row', alignItems: 'center', gap: 6 },
  badge: {
    minWidth: 20, height: 20, borderRadius: 10, backgroundColor: '#4F46E5',
    alignItems: 'center', justifyContent: 'center', paddingHorizontal: 4,
  },
  badgeText: { fontSize: 11, fontWeight: '700', color: '#fff' },
  overlay: { flex: 1, backgroundColor: 'rgba(0,0,0,0.45)', justifyContent: 'flex-end' },
  sheet: { backgroundColor: '#fff', borderTopLeftRadius: 20, borderTopRightRadius: 20, maxHeight: '75%' },
  header: {
    flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between',
    padding: 16, borderBottomWidth: 1, borderBottomColor: '#E5E7EB',
  },
  headerTitle: { fontSize: 16, fontWeight: '600', color: '#111827' },
  searchRow: {
    flexDirection: 'row', alignItems: 'center',
    margin: 12, borderWidth: 1, borderColor: '#E5E7EB',
    borderRadius: 10, paddingHorizontal: 10, backgroundColor: '#F9FAFB',
  },
  searchIcon: { marginRight: 6 },
  searchInput: { flex: 1, fontSize: 14, color: '#111827', paddingVertical: 8 },
  list: { flex: 1 },
  row: {
    flexDirection: 'row', alignItems: 'center', paddingHorizontal: 16,
    paddingVertical: 12, borderBottomWidth: 1, borderBottomColor: '#F3F4F6',
  },
  rowInfo: { flex: 1 },
  rowLabel: { fontSize: 14, color: '#111827', fontWeight: '500' },
  rowSublabel: { fontSize: 12, color: '#6B7280', marginTop: 2 },
  check: {
    width: 22, height: 22, borderRadius: 6, borderWidth: 2, borderColor: '#D1D5DB',
    alignItems: 'center', justifyContent: 'center',
  },
  checkSelected: { backgroundColor: '#4F46E5', borderColor: '#4F46E5' },
  empty: { padding: 24, alignItems: 'center' },
  emptyText: { fontSize: 14, color: '#9CA3AF' },
  footer: {
    flexDirection: 'row', gap: 12, padding: 16,
    borderTopWidth: 1, borderTopColor: '#E5E7EB',
  },
  clearBtn: {
    flex: 1, paddingVertical: 12, borderRadius: 10,
    borderWidth: 1, borderColor: '#D1D5DB', alignItems: 'center',
  },
  clearBtnText: { fontSize: 15, fontWeight: '600', color: '#374151' },
  doneBtn: { flex: 2, paddingVertical: 12, borderRadius: 10, backgroundColor: '#4F46E5', alignItems: 'center' },
  doneBtnText: { fontSize: 15, fontWeight: '600', color: '#fff' },
});
