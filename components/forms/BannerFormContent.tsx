// Elly Mobile App — BannerFormContent
// Extracted form body for the Banner create/edit screen.
// Keeps the parent screen file under 150 lines.

import { View, Text, StyleSheet, Pressable } from 'react-native';
import { Controller, UseFormReturn } from 'react-hook-form';
import { FormField } from './FormField';
import { StatusToggle } from './StatusToggle';
import { Button } from '../ui/Button';
import { BannerImagePicker, type PickedImage } from './BannerImagePicker';
import type { BannerFormValues } from '../../app/(drawer)/banners/[id]';
import type { BannerImages, BannerImageFiles } from '../../types/banner';

interface BannerFormContentProps {
  form: UseFormReturn<BannerFormValues>;
  isNew: boolean;
  isBusy: boolean;
  imageUrls?: BannerImages;
  imageFiles: BannerImageFiles;
  onImageChange: (slot: keyof BannerImageFiles, file: PickedImage | null) => void;
  onSubmit: (values: BannerFormValues) => void;
  onDelete: () => void;
}

const TARGET_OPTIONS: Array<{ value: BannerFormValues['target']; label: string }> = [
  { value: '_blank', label: 'Yeni sekme' },
  { value: '_self', label: 'Aynı sekme' },
];

const IMAGE_SLOTS: Array<{ key: keyof BannerImageFiles; label: string }> = [
  { key: 'desktop', label: 'Masaüstü' },
  { key: 'tablet', label: 'Tablet' },
  { key: 'mobile', label: 'Mobil' },
];

export function BannerFormContent({
  form,
  isNew,
  isBusy,
  imageUrls,
  imageFiles,
  onImageChange,
  onSubmit,
  onDelete,
}: BannerFormContentProps) {
  const { control, handleSubmit, watch, setValue } = form;
  const currentTarget = watch('target');

  return (
    <>
      {/* Section: Banner Bilgileri */}
      <View style={styles.card}>
        <Text style={styles.cardTitle}>Banner Bilgileri</Text>

        <FormField control={control} name="title" label="Başlık" placeholder="Banner başlığı" />
        <FormField control={control} name="altText" label="Alt Metin" placeholder="Resim alt metni (opsiyonel)" />
        <FormField control={control} name="link" label="Bağlantı URL" placeholder="https://ornek.com" />

        {/* Target toggle */}
        <View style={styles.fieldGroup}>
          <Text style={styles.fieldLabel}>Hedef</Text>
          <View style={styles.toggleRow}>
            {TARGET_OPTIONS.map((opt) => (
              <Pressable
                key={opt.value}
                style={[styles.toggleBtn, currentTarget === opt.value && styles.toggleBtnActive]}
                onPress={() => setValue('target', opt.value)}
              >
                <Text
                  style={[
                    styles.toggleBtnText,
                    currentTarget === opt.value && styles.toggleBtnTextActive,
                  ]}
                >
                  {opt.label}
                </Text>
              </Pressable>
            ))}
          </View>
        </View>

        <FormField control={control} name="type" label="Tür" placeholder="Banner türü (opsiyonel)" />
        <FormField control={control} name="orderIndex" label="Sıra" placeholder="0" />
        <FormField control={control} name="subFolder" label="Alt Klasör" placeholder="Alt klasör (opsiyonel)" />

        <Controller
          control={control}
          name="status"
          render={({ field }) => (
            <StatusToggle value={field.value} onChange={field.onChange} label="Durum" />
          )}
        />
      </View>

      {/* Section: Görseller */}
      <View style={styles.card}>
        <Text style={styles.cardTitle}>Görseller</Text>
        <Text style={styles.imageHint}>Seçilen resimler kaydet/güncelle butonuna basıldığında yüklenir.</Text>
        {IMAGE_SLOTS.map(({ key, label }) => (
          <BannerImagePicker
            key={key}
            label={label}
            existingUri={imageUrls?.[key]}
            value={imageFiles[key] ?? null}
            onChange={(file) => onImageChange(key, file)}
          />
        ))}
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
  toggleRow: {
    flexDirection: 'row',
    gap: 8,
  },
  toggleBtn: {
    flex: 1,
    paddingVertical: 8,
    paddingHorizontal: 12,
    borderRadius: 8,
    borderWidth: 1,
    borderColor: '#E5E7EB',
    alignItems: 'center',
    backgroundColor: '#F9FAFB',
  },
  toggleBtnActive: {
    backgroundColor: '#4F46E5',
    borderColor: '#4F46E5',
  },
  toggleBtnText: {
    fontSize: 14,
    color: '#374151',
    fontWeight: '500',
  },
  toggleBtnTextActive: {
    color: '#fff',
  },
  imageSlot: {
    marginBottom: 16,
    gap: 8,
  },
  imageSlotLabel: {
    fontSize: 13,
    fontWeight: '600',
    color: '#374151',
  },
  imagePreview: {
    width: '100%',
    height: 140,
    borderRadius: 8,
    backgroundColor: '#F3F4F6',
  },
  imageHint: {
    fontSize: 12,
    color: '#9CA3AF',
    marginBottom: 12,
  },
  actions: {
    gap: 12,
  },
  saveBtn: {
    flex: 1,
  },
});
