// Elly Mobile App — Page detail / edit screen
// Handles both editing an existing page (numeric id) and creating a new one (id="new").
// Uses react-hook-form + zod for validation, React Query mutations for persistence.

import { useEffect } from 'react';
import { ScrollView, StyleSheet, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useLocalSearchParams, useRouter } from 'expo-router';
import { useForm, Controller } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { z } from 'zod';
import { usePage, useCreatePage, useUpdatePage, useDeletePage } from '../../../hooks/usePages';
import { LoadingSpinner } from '../../../components/ui/LoadingSpinner';
import { ErrorView } from '../../../components/ui/ErrorView';
import { showConfirmDialog } from '../../../components/forms/ConfirmDialog';
import { PageFormContent } from '../../../components/forms/PageFormContent';
import type { PageFormData } from '../../../types/page';

export const pageSchema = z.object({
  title: z.string().min(1, 'Başlık zorunludur').max(100, 'Başlık 100 karakteri geçemez'),
  description: z.string().optional(),
  slug: z
    .string()
    .min(1, 'Slug zorunludur')
    .regex(/^[a-z0-9]+(?:-[a-z0-9]+)*$/, 'Slug sadece küçük harf, rakam ve tire içerebilir'),
  status: z.boolean().default(true),
  template: z.string().max(50).optional(),
  seoTitle: z.string().max(60).optional(),
  seoDescription: z.string().max(160).optional(),
  seoKeywords: z.string().optional(),
  noIndex: z.boolean().default(false),
  noFollow: z.boolean().default(false),
});

export type PageFormValues = z.infer<typeof pageSchema>;

export default function PageDetailScreen() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const router = useRouter();
  const isNew = id === 'new';
  const pageId = isNew ? 0 : Number(id);

  const { data, isLoading, isError, refetch } = usePage(pageId);
  const { mutate: createPage, isPending: isCreating } = useCreatePage();
  const { mutate: updatePage, isPending: isUpdating } = useUpdatePage();
  const { mutate: deletePage, isPending: isDeleting } = useDeletePage();

  const form = useForm<PageFormValues>({
    resolver: zodResolver(pageSchema),
    defaultValues: { status: true, noIndex: false, noFollow: false },
  });

  useEffect(() => {
    if (data) {
      form.reset({
        title: data.title,
        description: data.description ?? '',
        slug: data.slug,
        status: Boolean(data.status),
        template: data.template ?? '',
        seoTitle: data.seoInfo?.title ?? '',
        seoDescription: data.seoInfo?.description ?? '',
        seoKeywords: data.seoInfo?.keywords ?? '',
        noIndex: Boolean(data.seoInfo?.noIndex),
        noFollow: Boolean(data.seoInfo?.noFollow),
      });
    }
  }, [data, form]);

  function buildPayload(values: PageFormValues): PageFormData {
    return {
      title: values.title,
      description: values.description,
      slug: values.slug,
      status: values.status,
      template: values.template,
      seoInfo: {
        title: values.seoTitle ?? '',
        description: values.seoDescription ?? '',
        keywords: values.seoKeywords,
        noIndex: values.noIndex,
        noFollow: values.noFollow,
      },
    };
  }

  function onSubmit(values: PageFormValues) {
    const payload = buildPayload(values);
    if (isNew) {
      createPage(payload, { onSuccess: () => router.back() });
    } else {
      updatePage({ id: pageId, data: payload }, { onSuccess: () => router.back() });
    }
  }

  function handleDelete() {
    showConfirmDialog({
      onConfirm: () => deletePage(pageId, { onSuccess: () => router.back() }),
    });
  }

  if (!isNew && isLoading) return <LoadingSpinner />;
  if (!isNew && isError) {
    return <ErrorView message="Sayfa yüklenemedi." onRetry={() => refetch()} />;
  }

  const isBusy = isCreating || isUpdating || isDeleting;

  return (
    <SafeAreaView style={styles.safe} edges={['bottom']}>
      <ScrollView contentContainerStyle={styles.scroll} keyboardShouldPersistTaps="handled">
        <PageFormContent
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
