// Elly Mobile App — WidgetFormContent
// Extracted form body for the Widget create/edit screen.

import { View, Text, TouchableOpacity, StyleSheet } from 'react-native';
import { useThemeColor } from '../../hooks/useThemeColor';
import { Controller, type UseFormReturn } from 'react-hook-form';
import { FormField } from './FormField';
import { StatusToggle } from './StatusToggle';
import { Button } from '../ui/Button';
import { AiFieldButton } from '../ui/AiFieldButton';
import { useAiGenerate } from '../../hooks/useAiGenerate';
import { RelationPicker, type RelationItem } from './RelationPicker';
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
  bannerItems?: RelationItem[];
  postItems?: RelationItem[];
  selectedBannerIds: number[];
  selectedPostIds: number[];
  onBannerIdsChange: (ids: number[]) => void;
  onPostIdsChange: (ids: number[]) => void;
  onSubmit: (values: WidgetFormValues) => void;
  onDelete: () => void;
}

export function WidgetFormContent({
  form,
  isNew,
  isBusy,
  bannerItems = [],
  postItems = [],
  selectedBannerIds,
  selectedPostIds,
  onBannerIdsChange,
  onPostIdsChange,
  onSubmit,
  onDelete,
}: WidgetFormContentProps) {
  const { colors, isDark } = useThemeColor();
  const { control, handleSubmit, watch, setValue } = form;
  const selectedType = watch('type');
  const name = watch('name');
  const { descriptionLoading, handleAiDescription } = useAiGenerate();

  return (
    <>
      <View
        style={[
          styles.card,
          { backgroundColor: colors.surface, borderColor: isDark ? '#374151' : '#E5E7EB' },
        ]}
      >
        <Text style={[styles.cardTitle, { color: colors.text }]}>Widget Bilgileri</Text>
        <FormField control={control} name="name" label="Ad" placeholder="Widget adı" />
        <FormField
          control={control}
          name="description"
          label="Açıklama"
          placeholder="Kısa açıklama"
          multiline
          numberOfLines={3}
          rightElement={
            <AiFieldButton
              onClick={() =>
                handleAiDescription(name ?? '', 'widget', (desc) => setValue('description', desc))
              }
              isLoading={descriptionLoading}
              disabled={!name}
            />
          }
        />
        <FormField
          control={control}
          name="template"
          label="Şablon"
          placeholder="Şablon adı (opsiyonel)"
        />

        <View style={styles.fieldGroup}>
          <Text style={styles.fieldLabel}>Tür</Text>
          <View style={styles.typeRow}>
            {TYPE_OPTIONS.map((opt) => (
              <TouchableOpacity
                key={opt.value}
                style={[styles.chip, selectedType === opt.value && styles.chipActive]}
                onPress={() => setValue('type', opt.value)}
              >
                <Text
                  style={[styles.chipText, selectedType === opt.value && styles.chipTextActive]}
                >
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
                <TouchableOpacity
                  onPress={() => setValue('orderIndex', Math.max(0, field.value - 1))}
                >
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

      <View
        style={[
          styles.card,
          { backgroundColor: colors.surface, borderColor: isDark ? '#374151' : '#E5E7EB' },
        ]}
      >
        <Text style={[styles.cardTitle, { color: colors.text }]}>İlişkiler</Text>
        <RelationPicker
          label="Bannerlar"
          items={bannerItems}
          selectedIds={selectedBannerIds}
          onChange={onBannerIdsChange}
        />
        <RelationPicker
          label="Yazılar"
          items={postItems}
          selectedIds={selectedPostIds}
          onChange={onPostIdsChange}
        />
      </View>

      <View style={styles.actions}>
        <Button
          label={isNew ? 'Oluştur' : 'Güncelle'}
          onPress={handleSubmit(onSubmit)}
          loading={isBusy}
        />
        {!isNew && <Button label="Sil" onPress={onDelete} variant="danger" disabled={isBusy} />}
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
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 1 },
    shadowOpacity: 0.05,
    shadowRadius: 4,
    elevation: 2,
  },
  cardTitle: { fontSize: 15, fontWeight: '600', color: '#111827', marginBottom: 12 },
  fieldGroup: { marginBottom: 12 },
  fieldLabel: { fontSize: 14, fontWeight: '500', color: '#374151', marginBottom: 6 },
  typeRow: {
    flexDirection: 'row',
    backgroundColor: '#F3F4F6',
    borderRadius: 10,
    padding: 4,
  },
  chip: {
    flex: 1,
    paddingVertical: 8,
    borderRadius: 8,
    alignItems: 'center',
    justifyContent: 'center',
  },
  chipActive: {
    backgroundColor: '#FFFFFF',
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 1 },
    shadowOpacity: 0.1,
    shadowRadius: 2,
    elevation: 2,
  },
  chipText: {
    fontSize: 13,
    color: '#6B7280',
    fontWeight: '500',
  },
  chipTextActive: {
    color: '#111827',
    fontWeight: '600',
  },
  stepperRow: { flexDirection: 'row', alignItems: 'center', gap: 12 },
  stepper: { fontSize: 20, fontWeight: '600', color: '#4F46E5', paddingHorizontal: 8 },
  stepperValue: {
    fontSize: 16,
    fontWeight: '600',
    color: '#111827',
    minWidth: 32,
    textAlign: 'center',
  },
  actions: { gap: 12 },
});
