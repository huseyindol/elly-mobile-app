// Elly Mobile App — ContentFormContent
// Extracted form body for the Content create/edit screen.
// metadata is stored as a JSON string and parsed on save.

import { View, Text, StyleSheet } from 'react-native';
import { Controller, type UseFormReturn } from 'react-hook-form';
import { FormField } from './FormField';
import { StatusToggle } from './StatusToggle';
import { Button } from '../ui/Button';
import type { ContentFormValues } from '../../app/(drawer)/contents/[id]';

interface ContentFormContentProps {
  form: UseFormReturn<ContentFormValues>;
  isNew: boolean;
  isBusy: boolean;
  onSubmit: (values: ContentFormValues) => void;
  onDelete: () => void;
}

export function ContentFormContent({
  form,
  isNew,
  isBusy,
  onSubmit,
  onDelete,
}: ContentFormContentProps) {
  const { control, handleSubmit } = form;

  return (
    <>
      <View style={styles.card}>
        <Text style={styles.cardTitle}>Temel Bilgiler</Text>
        <FormField control={control} name="sectionKey" label="Bölüm Anahtarı" placeholder="ornek-bolum" />
        <FormField control={control} name="title" label="Başlık" placeholder="İçerik başlığı" />
        <FormField
          control={control}
          name="description"
          label="Açıklama"
          placeholder="Kısa açıklama"
          multiline
          numberOfLines={3}
        />
        <FormField control={control} name="contentType" label="İçerik Türü" placeholder="örn: hero, slider, card" />

        <View style={styles.fieldGroup}>
          <Text style={styles.fieldLabel}>Sıralama</Text>
          <Controller
            control={control}
            name="sortOrder"
            render={({ field }) => (
              <View style={styles.stepperRow}>
                <Text style={styles.stepper} onPress={() => field.onChange(Math.max(0, field.value - 1))}>−</Text>
                <Text style={styles.stepperValue}>{field.value}</Text>
                <Text style={styles.stepper} onPress={() => field.onChange(field.value + 1)}>+</Text>
              </View>
            )}
          />
        </View>

        <Controller
          control={control}
          name="isActive"
          render={({ field }) => (
            <StatusToggle value={field.value} onChange={field.onChange} label="Aktif" />
          )}
        />
      </View>

      <View style={styles.card}>
        <Text style={styles.cardTitle}>Metadata (JSON)</Text>
        <Text style={styles.metaHint}>Geçerli JSON formatında giriniz. Örn: {`{"key":"value"}`}</Text>
        <FormField
          control={control}
          name="metadata"
          placeholder={'{"key":"value"}'}
          multiline
          numberOfLines={6}
        />
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
  stepperRow: { flexDirection: 'row', alignItems: 'center', gap: 16 },
  stepper: { fontSize: 22, fontWeight: '600', color: '#4F46E5', paddingHorizontal: 8 },
  stepperValue: { fontSize: 16, fontWeight: '600', color: '#111827', minWidth: 32, textAlign: 'center' },
  metaHint: { fontSize: 12, color: '#9CA3AF', marginBottom: 8 },
  actions: { gap: 12 },
});
