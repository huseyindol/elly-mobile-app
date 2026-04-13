// Elly Mobile App — New Widget screen
// Standalone create form with relation pickers for banners and posts.

import { useState, useMemo } from 'react';
import { ScrollView, StyleSheet, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useRouter } from 'expo-router';
import { useThemeColor } from '../../../hooks/useThemeColor';
import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { useCreateWidget } from '../../../hooks/useWidgets';
import { useBannerList } from '../../../hooks/useBanners';
import { usePostList } from '../../../hooks/usePosts';
import { WidgetFormContent } from '../../../components/forms/WidgetFormContent';
import { widgetSchema } from './[id]';
import type { WidgetFormValues } from './[id]';
import type { WidgetFormData } from '../../../types/widget';

export default function NewWidgetScreen() {
  const { colors } = useThemeColor();

  const router = useRouter();
  const { mutate: createWidget, isPending } = useCreateWidget();

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

  function onSubmit(values: WidgetFormValues) {
    const payload: WidgetFormData = {
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
    createWidget(payload, { onSuccess: () => router.back() });
  }

  return (
    <SafeAreaView style={[styles.safe, { backgroundColor: colors.background }]} edges={['bottom']}>
      <ScrollView contentContainerStyle={styles.scroll} keyboardShouldPersistTaps="handled">
        <WidgetFormContent
          form={form}
          isNew
          isBusy={isPending}
          bannerItems={bannerItems}
          postItems={postItems}
          selectedBannerIds={selectedBannerIds}
          selectedPostIds={selectedPostIds}
          onBannerIdsChange={setSelectedBannerIds}
          onPostIdsChange={setSelectedPostIds}
          onSubmit={onSubmit}
          onDelete={() => router.back()}
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
