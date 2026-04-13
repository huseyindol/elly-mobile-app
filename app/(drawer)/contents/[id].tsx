// Elly Mobile App — Content detail / edit screen
// Handles both editing (UUID id) and creating (id="new") content items.
// metadata stored as JSON string, parsed to object on submit.

import { useEffect } from 'react';
import { ScrollView, StyleSheet, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useLocalSearchParams, useRouter } from 'expo-router';
import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { z } from 'zod';
import {
  useContent,
  useCreateContent,
  useUpdateContent,
  useDeleteContent,
} from '../../../hooks/useContents';
import { useThemeColor } from '../../../hooks/useThemeColor';
import { LoadingSpinner } from '../../../components/ui/LoadingSpinner';
import { ErrorView } from '../../../components/ui/ErrorView';
import { showConfirmDialog } from '../../../components/forms/ConfirmDialog';
import { ContentFormContent } from '../../../components/forms/ContentFormContent';
import type { ContentInput } from '../../../types/content';

export const contentSchema = z.object({
  sectionKey: z.string().min(1, 'Bölüm anahtarı zorunludur').max(100),
  title: z.string().min(1, 'Başlık zorunludur').max(200),
  description: z.string().optional(),
  isActive: z.boolean().default(true),
  sortOrder: z.coerce.number().int().min(0).default(0),
  contentType: z.string().min(1, 'İçerik türü zorunludur').max(50),
  metadata: z
    .string()
    .refine(
      (v) => {
        try {
          JSON.parse(v);
          return true;
        } catch {
          return false;
        }
      },
      { message: 'Geçerli JSON girin' }
    )
    .default('{}'),
});

export type ContentFormValues = z.infer<typeof contentSchema>;

export default function ContentDetailScreen() {
  const { colors } = useThemeColor();

  const { id } = useLocalSearchParams<{ id: string }>();
  const router = useRouter();
  const isNew = id === 'new';
  const contentId = isNew ? '' : String(id);

  const { data, isLoading, isError, refetch } = useContent(contentId);
  const { mutate: createContent, isPending: isCreating } = useCreateContent();
  const { mutate: updateContent, isPending: isUpdating } = useUpdateContent();
  const { mutate: deleteContent, isPending: isDeleting } = useDeleteContent();

  const form = useForm<ContentFormValues>({
    resolver: zodResolver(contentSchema),
    defaultValues: { isActive: true, sortOrder: 0, metadata: '{}' },
  });

  useEffect(() => {
    if (data?.data) {
      const d = data.data;
      form.reset({
        sectionKey: d.basicInfo.sectionKey,
        title: d.basicInfo.title,
        description: d.basicInfo.description ?? '',
        isActive: Boolean(d.basicInfo.isActive),
        sortOrder: d.basicInfo.sortOrder,
        contentType: d.contentType,
        metadata: JSON.stringify(d.metadata ?? {}, null, 2),
      });
    }
  }, [data, form]);

  function buildPayload(values: ContentFormValues): ContentInput {
    return {
      basicInfo: {
        sectionKey: values.sectionKey,
        title: values.title,
        description: values.description,
        isActive: values.isActive,
        sortOrder: values.sortOrder,
      },
      contentType: values.contentType,
      metadata: JSON.parse(values.metadata) as Record<string, unknown>,
    };
  }

  function onSubmit(values: ContentFormValues) {
    const payload = buildPayload(values);
    if (isNew) {
      createContent(payload, { onSuccess: () => router.back() });
    } else {
      updateContent({ id: contentId, data: payload }, { onSuccess: () => router.back() });
    }
  }

  function handleDelete() {
    showConfirmDialog({
      onConfirm: () => deleteContent(contentId, { onSuccess: () => router.back() }),
    });
  }

  if (!isNew && isLoading) return <LoadingSpinner />;
  if (!isNew && isError) {
    return <ErrorView message="İçerik yüklenemedi." onRetry={() => refetch()} />;
  }

  const isBusy = isCreating || isUpdating || isDeleting;

  return (
    <SafeAreaView style={[styles.safe, { backgroundColor: colors.background }]} edges={['bottom']}>
      <ScrollView contentContainerStyle={styles.scroll} keyboardShouldPersistTaps="handled">
        <ContentFormContent
          form={form}
          isNew={isNew}
          isBusy={isBusy}
          onSubmit={onSubmit}
          onDelete={handleDelete}
        />
        <View style={styles.bottomSpacer} />
      </ScrollView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  safe: { flex: 1, backgroundColor: '#F9FAFB' },
  scroll: { padding: 16 },
  bottomSpacer: { height: 32 },
});
