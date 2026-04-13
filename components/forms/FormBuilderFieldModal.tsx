// Elly Mobile App — FormBuilderFieldModal
// Modal for adding or editing a field in the form builder.
// Supports all FieldType values with optional options list for select/radio/multi_checkbox.

import React, { useState, useEffect } from 'react';
import {
  Modal,
  View,
  Text,
  TextInput,
  Switch,
  ScrollView,
  TouchableOpacity,
  StyleSheet,
  KeyboardAvoidingView,
  Platform,
} from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import type { FormField, FieldType, FieldOption } from '../../types/form';

const FIELD_TYPES: { type: FieldType; label: string }[] = [
  { type: 'text', label: 'Metin' },
  { type: 'email', label: 'E-posta' },
  { type: 'number', label: 'Sayı' },
  { type: 'select', label: 'Açılır Liste' },
  { type: 'checkbox', label: 'Onay Kutusu' },
  { type: 'multi_checkbox', label: 'Çoklu Onay' },
  { type: 'radio', label: 'Radyo Buton' },
  { type: 'textarea', label: 'Metin Alanı' },
  { type: 'date', label: 'Tarih' },
  { type: 'phone', label: 'Telefon' },
  { type: 'url', label: 'URL' },
];

const HAS_OPTIONS: FieldType[] = ['select', 'radio', 'multi_checkbox'];

interface FormBuilderFieldModalProps {
  visible: boolean;
  field: FormField | null;
  onSave: (field: FormField) => void;
  onClose: () => void;
}

function generateId(): string {
  return Math.random().toString(36).slice(2, 10);
}

export function FormBuilderFieldModal({
  visible,
  field,
  onSave,
  onClose,
}: FormBuilderFieldModalProps) {
  const [type, setType] = useState<FieldType>('text');
  const [label, setLabel] = useState('');
  const [placeholder, setPlaceholder] = useState('');
  const [required, setRequired] = useState(false);
  const [options, setOptions] = useState<FieldOption[]>([]);
  const [newOption, setNewOption] = useState('');

  useEffect(() => {
    if (field) {
      setType(field.type);
      setLabel(field.label);
      setPlaceholder(field.placeholder ?? '');
      setRequired(field.required ?? false);
      setOptions(field.options ?? []);
    } else {
      setType('text');
      setLabel('');
      setPlaceholder('');
      setRequired(false);
      setOptions([]);
    }
    setNewOption('');
  }, [field, visible]);

  function addOption() {
    const trimmed = newOption.trim();
    if (!trimmed) return;
    setOptions((prev) => [
      ...prev,
      { label: trimmed, value: trimmed.toLowerCase().replace(/\s+/g, '_') },
    ]);
    setNewOption('');
  }

  function removeOption(index: number) {
    setOptions((prev) => prev.filter((_, i) => i !== index));
  }

  function handleSave() {
    if (!label.trim()) return;
    const saved: FormField = {
      id: field?.id ?? generateId(),
      type,
      label: label.trim(),
      placeholder: placeholder.trim() || undefined,
      required,
      options: HAS_OPTIONS.includes(type) ? options : undefined,
    };
    onSave(saved);
  }

  return (
    <Modal visible={visible} animationType="slide" transparent onRequestClose={onClose}>
      <View style={styles.overlay}>
        <KeyboardAvoidingView
          behavior={Platform.OS === 'ios' ? 'padding' : undefined}
          style={styles.sheet}
        >
          <View style={styles.header}>
            <Text style={styles.headerTitle}>{field ? 'Alanı Düzenle' : 'Alan Ekle'}</Text>
            <TouchableOpacity onPress={onClose} hitSlop={{ top: 8, bottom: 8, left: 8, right: 8 }}>
              <Ionicons name="close" size={22} color="#374151" />
            </TouchableOpacity>
          </View>

          <ScrollView contentContainerStyle={styles.body} keyboardShouldPersistTaps="handled">
            {/* Type selector */}
            <Text style={styles.sectionLabel}>Alan Türü</Text>
            <ScrollView horizontal showsHorizontalScrollIndicator={false} style={styles.typeScroll}>
              {FIELD_TYPES.map((ft) => (
                <TouchableOpacity
                  key={ft.type}
                  style={[styles.typeChip, type === ft.type && styles.typeChipActive]}
                  onPress={() => setType(ft.type)}
                >
                  <Text
                    style={[styles.typeChipText, type === ft.type && styles.typeChipTextActive]}
                  >
                    {ft.label}
                  </Text>
                </TouchableOpacity>
              ))}
            </ScrollView>

            {/* Label */}
            <Text style={styles.fieldLabel}>Etiket *</Text>
            <TextInput
              style={[styles.input, !label.trim() && styles.inputError]}
              value={label}
              onChangeText={setLabel}
              placeholder="Alan etiketi"
              placeholderTextColor="#9CA3AF"
            />

            {/* Placeholder */}
            <Text style={styles.fieldLabel}>Placeholder (opsiyonel)</Text>
            <TextInput
              style={styles.input}
              value={placeholder}
              onChangeText={setPlaceholder}
              placeholder="Placeholder metni"
              placeholderTextColor="#9CA3AF"
            />

            {/* Required toggle */}
            <View style={styles.switchRow}>
              <Text style={styles.fieldLabel}>Zorunlu</Text>
              <Switch
                value={required}
                onValueChange={setRequired}
                trackColor={{ true: '#4F46E5' }}
              />
            </View>

            {/* Options — only for select / radio / multi_checkbox */}
            {HAS_OPTIONS.includes(type) && (
              <View>
                <Text style={styles.sectionLabel}>Seçenekler</Text>
                {options.map((opt, idx) => (
                  <View key={idx} style={styles.optionRow}>
                    <Text style={styles.optionLabel} numberOfLines={1}>
                      {opt.label}
                    </Text>
                    <TouchableOpacity onPress={() => removeOption(idx)}>
                      <Ionicons name="trash-outline" size={16} color="#EF4444" />
                    </TouchableOpacity>
                  </View>
                ))}
                <View style={styles.addOptionRow}>
                  <TextInput
                    style={[styles.input, styles.addOptionInput]}
                    value={newOption}
                    onChangeText={setNewOption}
                    placeholder="Yeni seçenek"
                    placeholderTextColor="#9CA3AF"
                    returnKeyType="done"
                    onSubmitEditing={addOption}
                  />
                  <TouchableOpacity style={styles.addOptionBtn} onPress={addOption}>
                    <Ionicons name="add" size={20} color="#fff" />
                  </TouchableOpacity>
                </View>
              </View>
            )}
          </ScrollView>

          {/* Footer */}
          <View style={styles.footer}>
            <TouchableOpacity style={styles.cancelBtn} onPress={onClose}>
              <Text style={styles.cancelBtnText}>İptal</Text>
            </TouchableOpacity>
            <TouchableOpacity
              style={[styles.saveBtn, !label.trim() && styles.saveBtnDisabled]}
              onPress={handleSave}
              disabled={!label.trim()}
            >
              <Text style={styles.saveBtnText}>Kaydet</Text>
            </TouchableOpacity>
          </View>
        </KeyboardAvoidingView>
      </View>
    </Modal>
  );
}

const styles = StyleSheet.create({
  overlay: {
    flex: 1,
    backgroundColor: 'rgba(0,0,0,0.45)',
    justifyContent: 'flex-end',
  },
  sheet: {
    backgroundColor: '#fff',
    borderTopLeftRadius: 20,
    borderTopRightRadius: 20,
    maxHeight: '85%',
  },
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    padding: 16,
    borderBottomWidth: 1,
    borderBottomColor: '#E5E7EB',
  },
  headerTitle: { fontSize: 16, fontWeight: '600', color: '#111827' },
  body: { padding: 16, gap: 4 },
  sectionLabel: {
    fontSize: 13,
    fontWeight: '600',
    color: '#6B7280',
    marginBottom: 8,
    marginTop: 4,
    textTransform: 'uppercase',
    letterSpacing: 0.5,
  },
  fieldLabel: { fontSize: 14, fontWeight: '500', color: '#374151', marginBottom: 4, marginTop: 8 },
  input: {
    borderWidth: 1,
    borderColor: '#D1D5DB',
    borderRadius: 8,
    paddingHorizontal: 12,
    paddingVertical: 10,
    fontSize: 14,
    color: '#111827',
    backgroundColor: '#FAFAFA',
    marginBottom: 4,
  },
  inputError: { borderColor: '#EF4444' },
  switchRow: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    marginTop: 8,
    marginBottom: 4,
  },
  typeScroll: { marginBottom: 8 },
  typeChip: {
    paddingHorizontal: 12,
    paddingVertical: 7,
    borderRadius: 20,
    borderWidth: 1,
    borderColor: '#D1D5DB',
    marginRight: 8,
    backgroundColor: '#fff',
  },
  typeChipActive: { backgroundColor: '#4F46E5', borderColor: '#4F46E5' },
  typeChipText: { fontSize: 13, color: '#374151' },
  typeChipTextActive: { color: '#fff', fontWeight: '600' },
  optionRow: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingVertical: 8,
    paddingHorizontal: 10,
    backgroundColor: '#F9FAFB',
    borderRadius: 8,
    marginBottom: 4,
    borderWidth: 1,
    borderColor: '#E5E7EB',
  },
  optionLabel: { fontSize: 14, color: '#374151', flex: 1, marginRight: 8 },
  addOptionRow: { flexDirection: 'row', alignItems: 'center', gap: 8, marginTop: 4 },
  addOptionInput: { flex: 1, marginBottom: 0 },
  addOptionBtn: {
    backgroundColor: '#4F46E5',
    borderRadius: 8,
    padding: 10,
  },
  footer: {
    flexDirection: 'row',
    gap: 12,
    padding: 16,
    borderTopWidth: 1,
    borderTopColor: '#E5E7EB',
  },
  cancelBtn: {
    flex: 1,
    paddingVertical: 12,
    borderRadius: 10,
    borderWidth: 1,
    borderColor: '#D1D5DB',
    alignItems: 'center',
  },
  cancelBtnText: { fontSize: 15, fontWeight: '600', color: '#374151' },
  saveBtn: {
    flex: 1,
    paddingVertical: 12,
    borderRadius: 10,
    backgroundColor: '#4F46E5',
    alignItems: 'center',
  },
  saveBtnDisabled: { backgroundColor: '#A5B4FC' },
  saveBtnText: { fontSize: 15, fontWeight: '600', color: '#fff' },
});
