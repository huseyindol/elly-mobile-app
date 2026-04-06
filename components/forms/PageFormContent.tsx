// Elly Mobile App — PageFormContent
// Extracted form body for the Page create/edit screen.
// Keeps the parent screen file under 150 lines.

import { View, Text, StyleSheet } from 'react-native';
import { Controller, UseFormReturn } from 'react-hook-form';
import { FormField } from './FormField';
import { StatusToggle } from './StatusToggle';
import { SeoInfoSection } from './SeoInfoForm';
import { Button } from '../ui/Button';
import type { PageFormValues } from '../../app/(drawer)/pages/[id]';

interface PageFormContentProps {
  form: UseFormReturn<PageFormValues>;
  isNew: boolean;
  isBusy: boolean;
  onSubmit: (values: PageFormValues) => void;
  onDelete: () => void;
}

export function PageFormContent({ form, isNew, isBusy, onSubmit, onDelete }: PageFormContentProps) {
  const { control, handleSubmit } = form;

  return (
    <>
      {/* Section: Sayfa Bilgileri */}
      <View style={styles.card}>
        <Text style={styles.cardTitle}>Sayfa Bilgileri</Text>

        <FormField control={control} name="title" label="Başlık" placeholder="Sayfa başlığı" />
        <FormField
          control={control}
          name="description"
          label="Açıklama"
          placeholder="Kısa açıklama"
          multiline
          numberOfLines={3}
        />
        <FormField control={control} name="slug" label="Slug" placeholder="ornek-sayfa-slug" />
        <FormField control={control} name="template" label="Şablon" placeholder="Şablon adı (opsiyonel)" />

        <Controller
          control={control}
          name="status"
          render={({ field }) => (
            <StatusToggle value={field.value} onChange={field.onChange} label="Durum" />
          )}
        />
      </View>

      {/* Section: SEO Ayarları */}
      <SeoInfoSection>
        <FormField control={control} name="seoTitle" label="SEO Başlığı" placeholder="60 karakter maks." />
        <FormField
          control={control}
          name="seoDescription"
          label="SEO Açıklaması"
          placeholder="160 karakter maks."
          multiline
          numberOfLines={3}
        />
        <FormField control={control} name="seoKeywords" label="Anahtar Kelimeler" placeholder="kelime1, kelime2" />

        <Controller
          control={control}
          name="noIndex"
          render={({ field }) => (
            <StatusToggle value={field.value} onChange={field.onChange} label="No Index" />
          )}
        />
        <Controller
          control={control}
          name="noFollow"
          render={({ field }) => (
            <StatusToggle value={field.value} onChange={field.onChange} label="No Follow" />
          )}
        />
      </SeoInfoSection>

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
  actions: {
    gap: 12,
  },
  saveBtn: {
    flex: 1,
  },
});
