// Elly Mobile App — Widget detail / edit screen
// Handles both editing an existing widget (numeric id) and creating a new one (id="new").
// Includes relation pickers for banners and posts.

import { useEffect, useState, useMemo } from 'react';
import { ScrollView, StyleSheet, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useLocalSearchParams, useRouter } from 'expo-router';
import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { z } from 'zod';
import {
  useWidget,
  useCreateWidget,
  useUpdateWidget,
  useDeleteWidget,
} from '../../../hooks/useWidgets';
import { useThemeColor } from '../../../hooks/useThemeColor';
import { useBannerList } from '../../../hooks/useBanners';
import { usePostList } from '../../../hooks/usePosts';
import { LoadingSpinner } from '../../../components/ui/LoadingSpinner';
import { ErrorView } from '../../../components/ui/ErrorView';
import { showConfirmDialog } from '../../../components/forms/ConfirmDialog';
import { WidgetFormContent } from '../../../components/forms/WidgetFormContent';
import type { WidgetFormData } from '../../../types/widget';

export const widgetSchema = z.object({
  name: z.string().min(1, 'Ad zorunludur').max(100),
  description: z.string().optional(),
  type: z.enum(['BANNER', 'POST']),
  content: z.string().optional(),
  orderIndex: z.coerce.number().int().min(0).default(0),
  status: z.boolean().default(true),
  template: z.string().max(50).optional(),
});

export type WidgetFormValues = z.infer<typeof widgetSchema>;

export default function WidgetDetailScreen() {
  const { colors } = useThemeColor();

  const { id } = useLocalSearchParams<{ id: string }>();
  const router = useRouter();
  const isNew = id === 'new';
  const widgetId = isNew ? 0 : Number(id);

  const { data, isLoading, isError, refetch } = useWidget(widgetId);
  const { mutate: createWidget, isPending: isCreating } = useCreateWidget();
  const { mutate: updateWidget, isPending: isUpdating } = useUpdateWidget();
  const { mutate: deleteWidget, isPending: isDeleting } = useDeleteWidget();

  const { data: bannersData } = useBannerList();
  const { data: postsData } = usePostList();

  const [selectedBannerIds, setSelectedBannerIds] = useState<number[]>([]);
  const [selectedPostIds, setSelectedPostIds] = useState<number[]>([]);

  const bannerItems = useMemo(
    () =>
      (bannersData?.data ?? []).map((b) => ({ id: b.id, label: b.title, sublabel: b.subFolder })),
    [bannersData]
  );
  const postItems = useMemo(
    () => (postsData?.data ?? []).map((p) => ({ id: p.id, label: p.title, sublabel: p.slug })),
    [postsData]
  );

  const form = useForm<WidgetFormValues>({
    resolver: zodResolver(widgetSchema),
    defaultValues: { status: true, orderIndex: 0, type: 'BANNER' },
  });

  useEffect(() => {
    if (data?.data) {
      const d = data.data;
      form.reset({
        name: d.name,
        description: d.description ?? '',
        type: d.type,
        content: d.content ?? '',
        orderIndex: d.orderIndex,
        status: Boolean(d.status),
        template: d.template ?? '',
      });
      setSelectedBannerIds((d.banners ?? []).map((b) => b.id));
      setSelectedPostIds((d.posts ?? []).map((p) => p.id));
    }
  }, [data, form]);

  function buildPayload(values: WidgetFormValues): WidgetFormData {
    return {
      name: values.name,
      description: values.description,
      type: values.type,
      content: values.content,
      orderIndex: values.orderIndex,
      status: values.status,
      template: values.template,
      bannerIds: selectedBannerIds,
      postIds: selectedPostIds,
    };
  }

  function onSubmit(values: WidgetFormValues) {
    const payload = buildPayload(values);
    if (isNew) {
      createWidget(payload, { onSuccess: () => router.back() });
    } else {
      updateWidget({ id: widgetId, data: payload }, { onSuccess: () => router.back() });
    }
  }

  function handleDelete() {
    showConfirmDialog({
      onConfirm: () => deleteWidget(widgetId, { onSuccess: () => router.back() }),
    });
  }

  if (!isNew && isLoading) return <LoadingSpinner />;
  if (!isNew && isError) {
    return <ErrorView message="Widget yüklenemedi." onRetry={() => refetch()} />;
  }

  const isBusy = isCreating || isUpdating || isDeleting;

  return (
    <SafeAreaView style={[styles.safe, { backgroundColor: colors.background }]} edges={['bottom']}>
      <ScrollView contentContainerStyle={styles.scroll} keyboardShouldPersistTaps="handled">
        <WidgetFormContent
          form={form}
          isNew={isNew}
          isBusy={isBusy}
          bannerItems={bannerItems}
          postItems={postItems}
          selectedBannerIds={selectedBannerIds}
          selectedPostIds={selectedPostIds}
          onBannerIdsChange={setSelectedBannerIds}
          onPostIdsChange={setSelectedPostIds}
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
