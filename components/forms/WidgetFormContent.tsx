// Elly Mobile App — WidgetFormContent
// Extracted form body for the Widget create/edit screen.

import { View, Text, TouchableOpacity, StyleSheet } from 'react-native';
import { Controller, type UseFormReturn } from 'react-hook-form';
import { FormField } from './FormField';
import { StatusToggle } from './StatusToggle';
import { Button } from '../ui/Button';
import type { WidgetFormValues } from '../../app/(drawer)/widgets/[id]';
import type { WidgetType } from '../../types/widget';

const TYPE_OPTIONS: { value: WidgetType; label: string }[] = [
  { value: 'BANNER', label: 'Banner' },
  { value: 'POST', label: 'Yazı' },
];

interface WidgetFormContentProps {
  form: UseFormReturn<WidgetFormValues>;
  isNew: boolean;
  isBusy: boolean;
  onSubmit: (values: WidgetFormValues) => void;
  onDelete: () => void;
}

export function WidgetFormContent({
  form,
  isNew,
  isBusy,
  onSubmit,
  onDelete,
}: WidgetFormContentProps) {
  const { control, handleSubmit, watch, setValue } = form;
  const selectedType = watch('type');

  return (
    <>
      <View style={styles.card}>
        <Text style={styles.cardTitle}>Widget Bilgileri</Text>
        <FormField control={control} name="name" label="Ad" placeholder="Widget adı" />
        <FormField
          control={control}
          name="description"
          label="Açıklama"
          placeholder="Kısa açıklama"
          multiline
          numberOfLines={3}
        />
        <FormField control={control} name="template" label="Şablon" placeholder="Şablon adı (opsiyonel)" />

        <View style={styles.fieldGroup}>
          <Text style={styles.fieldLabel}>Tür</Text>
          <View style={styles.typeRow}>
            {TYPE_OPTIONS.map((opt) => (
              <TouchableOpacity
                key={opt.value}
                style={[styles.chip, selectedType === opt.value && styles.chipActive]}
                onPress={() => setValue('type', opt.value)}
              >
                <Text style={[styles.chipText, selectedType === opt.value && styles.chipTextActive]}>
                  {opt.label}
                </Text>
              </TouchableOpacity>
            ))}
          </View>
        </View>

        <FormField
          control={control}
          name="content"
          label="İçerik"
          placeholder="İçerik metni veya konfigürasyon"
          multiline
          numberOfLines={4}
        />

        <View style={styles.fieldGroup}>
          <Text style={styles.fieldLabel}>Sipariş No</Text>
          <Controller
            control={control}
            name="orderIndex"
            render={({ field }) => (
              <View style={styles.stepperRow}>
                <TouchableOpacity onPress={() => setValue('orderIndex', Math.max(0, field.value - 1))}>
                  <Text style={styles.stepper}>−</Text>
                </TouchableOpacity>
                <Text style={styles.stepperValue}>{field.value}</Text>
                <TouchableOpacity onPress={() => setValue('orderIndex', field.value + 1)}>
                  <Text style={styles.stepper}>+</Text>
                </TouchableOpacity>
              </View>
            )}
          />
        </View>

        <Controller
          control={control}
          name="status"
          render={({ field }) => (
            <StatusToggle value={field.value} onChange={field.onChange} label="Durum" />
          )}
        />
      </View>

      <View style={styles.card}>
        <Text style={styles.cardTitle}>İlişkiler</Text>
        <Text style={styles.relationHint}>Banner ve yazı bağlantısı yönetimi yakında eklenecek.</Text>
      </View>

      <View style={styles.actions}>
        <Button
          label={isNew ? 'Oluştur' : 'Güncelle'}
          onPress={handleSubmit(onSubmit)}
          loading={isBusy}
        />
        {!isNew && (
          <Button label="Sil" onPress={onDelete} variant="danger" disabled={isBusy} />
        )}
      </View>
    </>
  );
}

const styles = StyleSheet.create({
  card: {
    backgroundColor: '#fff', borderRadius: 12, padding: 16, marginBottom: 16,
    shadowColor: '#000', shadowOffset: { width: 0, height: 1 },
    shadowOpacity: 0.05, shadowRadius: 4, elevation: 2,
  },
  cardTitle: { fontSize: 15, fontWeight: '600', color: '#111827', marginBottom: 12 },
  fieldGroup: { marginBottom: 12 },
  fieldLabel: { fontSize: 14, fontWeight: '500', color: '#374151', marginBottom: 6 },
  typeRow: { flexDirection: 'row', gap: 8 },
  chip: {
    paddingHorizontal: 14, paddingVertical: 8, borderRadius: 8,
    borderWidth: 1, borderColor: '#E5E7EB', backgroundColor: '#F9FAFB',
  },
  chipActive: { borderColor: '#4F46E5', backgroundColor: '#EEF2FF' },
  chipText: { fontSize: 13, color: '#6B7280', fontWeight: '500' },
  chipTextActive: { color: '#4F46E5' },
  stepperRow: { flexDirection: 'row', alignItems: 'center', gap: 12 },
  stepper: { fontSize: 20, fontWeight: '600', color: '#4F46E5', paddingHorizontal: 8 },
  stepperValue: { fontSize: 16, fontWeight: '600', color: '#111827', minWidth: 32, textAlign: 'center' },
  relationHint: { fontSize: 14, color: '#9CA3AF', lineHeight: 20 },
  actions: { gap: 12 },
});
