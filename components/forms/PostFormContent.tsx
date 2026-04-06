// Elly Mobile App — PostFormContent
// Extracted form body for the Post create/edit screen.
// Keeps the parent screen file under 150 lines.

import { View, Text, StyleSheet } from 'react-native';
import { Controller, UseFormReturn } from 'react-hook-form';
import { FormField } from './FormField';
import { StatusToggle } from './StatusToggle';
import { SeoInfoSection } from './SeoInfoForm';
import { Button } from '../ui/Button';
import { Input } from '../ui/Input';
import type { PostFormValues } from '../../app/(drawer)/posts/[id]';

interface PostFormContentProps {
  form: UseFormReturn<PostFormValues>;
  isNew: boolean;
  isBusy: boolean;
  onSubmit: (values: PostFormValues) => void;
  onDelete: () => void;
}

export function PostFormContent({ form, isNew, isBusy, onSubmit, onDelete }: PostFormContentProps) {
  const { control, handleSubmit } = form;

  return (
    <>
      {/* Section: Yazı Bilgileri */}
      <View style={styles.card}>
        <Text style={styles.cardTitle}>Yazı Bilgileri</Text>

        <FormField control={control} name="title" label="Başlık" placeholder="Yazı başlığı" />
        <FormField control={control} name="slug" label="Slug" placeholder="ornek-yazi-slug" />
        <FormField
          control={control}
          name="content"
          label="İçerik"
          placeholder="Yazı içeriği..."
          multiline
          numberOfLines={6}
        />
        <Controller
          control={control}
          name="orderIndex"
          render={({ field, fieldState }) => (
            <Input
              label="Sıra"
              placeholder="0"
              value={String(field.value ?? 0)}
              onChangeText={(text) => field.onChange(text === '' ? 0 : parseInt(text, 10))}
              error={fieldState.error?.message}
            />
          )}
        />
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
