import { useState } from 'react';
import { View, Text, StyleSheet } from 'react-native';
import { useThemeColor } from '../../hooks/useThemeColor';
import { Controller, UseFormReturn } from 'react-hook-form';
import { FormField } from './FormField';
import { StatusToggle } from './StatusToggle';
import { ModernSwitch } from './ModernSwitch';
import { SeoInfoSection } from './SeoInfoForm';
import { Button } from '../ui/Button';
import { Input } from '../ui/Input';
import { AiFieldButton } from '../ui/AiFieldButton';
import { AiArticlePanel } from '../posts/AiArticlePanel';
import { RichTextEditor } from '../ui/RichTextEditor';
import { useAiGenerate } from '../../hooks/useAiGenerate';
import type { PostFormValues } from '../../app/(drawer)/posts/[id]';

interface PostFormContentProps {
  form: UseFormReturn<PostFormValues>;
  isNew: boolean;
  isBusy: boolean;
  onSubmit: (values: PostFormValues) => void;
  onDelete: () => void;
}

export function PostFormContent({ form, isNew, isBusy, onSubmit, onDelete }: PostFormContentProps) {
  const { colors, isDark } = useThemeColor();

  const { control, handleSubmit, watch, setValue } = form;
  const title = watch('title');
  const [showAiPanel, setShowAiPanel] = useState(false);
  const { slugLoading, seoLoading, handleAiSlug, handleAiSeo } = useAiGenerate();

  return (
    <>
      <View
        style={[
          styles.card,
          { backgroundColor: colors.surface, borderColor: isDark ? '#374151' : '#E5E7EB' },
        ]}
      >
        <Text style={[styles.cardTitle, { color: colors.text }]}>Yazı Bilgileri</Text>

        <FormField control={control} name="title" label="Başlık" placeholder="Yazı başlığı" />
        <FormField
          control={control}
          name="slug"
          label="Slug"
          placeholder="ornek-yazi-slug"
          rightElement={
            <AiFieldButton
              onClick={() => handleAiSlug(title ?? '', (slug) => setValue('slug', slug))}
              isLoading={slugLoading}
              disabled={!title}
            />
          }
        />
        <Controller
          control={control}
          name="content"
          render={({ field, fieldState }) => (
            <RichTextEditor
              label="İçerik"
              value={(field.value as string) ?? ''}
              onChange={field.onChange}
              error={fieldState.error?.message}
              rightElement={
                <AiFieldButton
                  label={showAiPanel ? 'AI Panel (Gizle)' : 'AI Panel (Aç)'}
                  onClick={() => setShowAiPanel(!showAiPanel)}
                  isLoading={false}
                />
              }
            />
          )}
        />
        {showAiPanel && <AiArticlePanel onGenerated={(html) => setValue('content', html)} />}

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
        <FormField
          control={control}
          name="template"
          label="Şablon"
          placeholder="Şablon adı (opsiyonel)"
        />

        <Controller
          control={control}
          name="status"
          render={({ field }) => (
            <StatusToggle value={field.value} onChange={field.onChange} label="Durum" />
          )}
        />
      </View>

      <SeoInfoSection
        rightElement={
          <AiFieldButton
            label="AI ile doldur"
            onClick={() =>
              handleAiSeo(title ?? '', (seo) => {
                setValue('seoTitle', seo.seoTitle);
                setValue('seoDescription', seo.seoDescription);
                setValue('seoKeywords', seo.seoKeywords);
              })
            }
            isLoading={seoLoading}
            disabled={!title}
          />
        }
      >
        <FormField
          control={control}
          name="seoTitle"
          label="SEO Başlığı"
          placeholder="60 karakter maks."
        />
        <FormField
          control={control}
          name="seoDescription"
          label="SEO Açıklaması"
          placeholder="160 karakter maks."
          multiline
          numberOfLines={3}
        />
        <FormField
          control={control}
          name="seoKeywords"
          label="Anahtar Kelimeler"
          placeholder="kelime1, kelime2"
        />

        <Controller
          control={control}
          name="noIndex"
          render={({ field }) => (
            <ModernSwitch
              value={field.value}
              onChange={field.onChange}
              label="No Index"
              description="Arama motorlarında indekslenmeyi engeller."
            />
          )}
        />
        <Controller
          control={control}
          name="noFollow"
          render={({ field }) => (
            <ModernSwitch
              value={field.value}
              onChange={field.onChange}
              label="No Follow"
              description="Yazıdaki linklerin takip edilmesini engeller."
            />
          )}
        />
      </SeoInfoSection>

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
