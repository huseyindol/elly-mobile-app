// Elly Mobile App — ComponentFormContent
// Extracted form body for the Component create/edit screen.
// Keeps the parent screen file under 150 lines.

import { View, Text, Pressable, StyleSheet } from 'react-native';
import { Controller, UseFormReturn } from 'react-hook-form';
import { FormField } from './FormField';
import { StatusToggle } from './StatusToggle';
import { Button } from '../ui/Button';
import type { ComponentFormValues } from '../../app/(drawer)/components/[id]';
import type { ComponentType } from '../../types/component';

interface ComponentFormContentProps {
  form: UseFormReturn<ComponentFormValues>;
  isNew: boolean;
  isBusy: boolean;
  onSubmit: (values: ComponentFormValues) => void;
  onDelete: () => void;
}

const TYPE_OPTIONS: Array<{ value: ComponentType; label: string }> = [
  { value: 'BANNER', label: 'Banner' },
  { value: 'WIDGET', label: 'Widget' },
  { value: 'FORM', label: 'Form' },
];

export function ComponentFormContent({
  form,
  isNew,
  isBusy,
  onSubmit,
  onDelete,
}: ComponentFormContentProps) {
  const { control, handleSubmit, watch, setValue } = form;
  const currentType = watch('type');

  return (
    <>
      {/* Section: Bileşen Bilgileri */}
      <View style={styles.card}>
        <Text style={styles.cardTitle}>Bileşen Bilgileri</Text>

        <FormField control={control} name="name" label="Ad" placeholder="Bileşen adı" />
        <FormField
          control={control}
          name="description"
          label="Açıklama"
          placeholder="Kısa açıklama (opsiyonel)"
          multiline
          numberOfLines={3}
        />

        {/* Type selector */}
        <View style={styles.fieldGroup}>
          <Text style={styles.fieldLabel}>Tür</Text>
          <View style={styles.typeRow}>
            {TYPE_OPTIONS.map((opt) => (
              <Pressable
                key={opt.value}
                style={[styles.typeBtn, currentType === opt.value && styles.typeBtnActive]}
                onPress={() => setValue('type', opt.value)}
              >
                <Text
                  style={[
                    styles.typeBtnText,
                    currentType === opt.value && styles.typeBtnTextActive,
                  ]}
                >
                  {opt.label}
                </Text>
              </Pressable>
            ))}
          </View>
        </View>

        <FormField
          control={control}
          name="content"
          label="İçerik"
          placeholder="İçerik (opsiyonel)"
          multiline
          numberOfLines={4}
        />
        <FormField control={control} name="orderIndex" label="Sıra" placeholder="0" />
        <FormField control={control} name="template" label="Şablon" placeholder="Şablon adı (opsiyonel)" />

        <Controller
          control={control}
          name="status"
          render={({ field }) => (
            <StatusToggle value={field.value} onChange={field.onChange} label="Durum" />
          )}
        />
      </View>

      {/* Section: İlişkiler */}
      <View style={styles.card}>
        <Text style={styles.cardTitle}>İlişkiler</Text>
        <View style={styles.infoBadge}>
          <Text style={styles.infoBadgeText}>İlişki yönetimi yakında</Text>
        </View>
      </View>

      {/* Action buttons */}
      <View style={styles.actions}>
        <View style={styles.saveBtn}>
          <Button
            label={isNew ? 'Oluştur' : 'Kaydet'}
            onPress={handleSubmit(onSubmit)}
            variant="primary"
            icon="checkmark-outline"
            loading={isBusy}
          />
        </View>
        {!isNew && (
          <Button
            label="Sil"
            onPress={onDelete}
            variant="danger"
            icon="trash-outline"
            disabled={isBusy}
          />
        )}
      </View>
    </>
  );
}

const styles = StyleSheet.create({
  card: {
    backgroundColor: '#fff',
    borderRadius: 12,
    padding: 16,
    marginBottom: 16,
    borderWidth: 1,
    borderColor: '#E5E7EB',
    gap: 4,
  },
  cardTitle: {
    fontSize: 15,
    fontWeight: '600',
    color: '#111827',
    marginBottom: 12,
  },
  fieldGroup: {
    marginVertical: 6,
  },
  fieldLabel: {
    fontSize: 13,
    fontWeight: '500',
    color: '#374151',
    marginBottom: 8,
  },
  typeRow: {
    flexDirection: 'row',
    gap: 8,
  },
  typeBtn: {
    flex: 1,
    paddingVertical: 8,
    paddingHorizontal: 4,
    borderRadius: 8,
    borderWidth: 1,
    borderColor: '#E5E7EB',
    alignItems: 'center',
    backgroundColor: '#F9FAFB',
  },
  typeBtnActive: {
    backgroundColor: '#4F46E5',
    borderColor: '#4F46E5',
  },
  typeBtnText: {
    fontSize: 13,
    color: '#374151',
    fontWeight: '500',
  },
  typeBtnTextActive: {
    color: '#fff',
  },
  infoBadge: {
    padding: 12,
    borderRadius: 8,
    backgroundColor: '#EEF2FF',
    alignItems: 'center',
  },
  infoBadgeText: {
    fontSize: 13,
    color: '#6366F1',
    fontWeight: '500',
  },
  actions: {
    gap: 12,
  },
  saveBtn: {
    flex: 1,
  },
});
