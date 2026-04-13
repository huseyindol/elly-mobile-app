// Elly Mobile App — Banner detail / edit screen
// Handles both editing an existing banner (numeric id) and creating a new one (id="new").
// Uses react-hook-form + zod for validation, React Query mutations for persistence.
// Image files managed in local state; sent as multipart/form-data via useBanner mutations.

import { useEffect, useState, useCallback } from 'react';
import { ScrollView, StyleSheet, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useLocalSearchParams, useRouter } from 'expo-router';
import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { z } from 'zod';
import {
  useBanner,
  useCreateBanner,
  useUpdateBanner,
  useDeleteBanner,
} from '../../../hooks/useBanners';
import { useThemeColor } from '../../../hooks/useThemeColor';
import { LoadingSpinner } from '../../../components/ui/LoadingSpinner';
import { ErrorView } from '../../../components/ui/ErrorView';
import { showConfirmDialog } from '../../../components/forms/ConfirmDialog';
import { BannerFormContent } from '../../../components/forms/BannerFormContent';
import type { PickedImage } from '../../../components/forms/BannerImagePicker';
import type { BannerFormData, BannerImageFiles } from '../../../types/banner';

export const bannerSchema = z.object({
  title: z.string().min(1, 'Başlık zorunludur').max(100),
  altText: z.string().optional(),
  link: z.string().url('Geçerli bir URL girin').optional().or(z.literal('')),
  target: z.enum(['_blank', '_self']).default('_blank'),
  type: z.string().optional(),
  orderIndex: z.coerce.number().int().min(0).default(0),
  status: z.boolean().default(true),
  subFolder: z.string().optional(),
});

export type BannerFormValues = z.infer<typeof bannerSchema>;

export default function BannerDetailScreen() {
  const { colors } = useThemeColor();

  const { id } = useLocalSearchParams<{ id: string }>();
  const router = useRouter();
  const isNew = id === 'new';
  const bannerId = isNew ? 0 : Number(id);

  const { data, isLoading, isError, refetch } = useBanner(bannerId);
  const { mutate: createBanner, isPending: isCreating } = useCreateBanner();
  const { mutate: updateBanner, isPending: isUpdating } = useUpdateBanner();
  const { mutate: deleteBanner, isPending: isDeleting } = useDeleteBanner();

  const [imageFiles, setImageFiles] = useState<BannerImageFiles>({});

  const form = useForm<BannerFormValues>({
    resolver: zodResolver(bannerSchema),
    defaultValues: { status: true, target: '_blank', orderIndex: 0 },
  });

  useEffect(() => {
    if (data) {
      const d = data;
      form.reset({
        title: d.title,
        altText: d.altText ?? '',
        link: d.link ?? '',
        target: d.target,
        type: d.type ?? '',
        orderIndex: d.orderIndex,
        status: Boolean(d.status),
        subFolder: d.subFolder ?? '',
      });
    }
  }, [data, form]);

  const handleImageChange = useCallback(
    (slot: keyof BannerImageFiles, file: PickedImage | null) => {
      setImageFiles((prev) => {
        if (file === null) {
          const next = { ...prev };
          delete next[slot];
          return next;
        }
        return { ...prev, [slot]: file };
      });
    },
    []
  );

  function buildPayload(values: BannerFormValues): BannerFormData {
    return {
      title: values.title,
      altText: values.altText,
      link: values.link,
      target: values.target,
      type: values.type,
      orderIndex: values.orderIndex,
      status: values.status,
      subFolder: values.subFolder,
    };
  }

  function onSubmit(values: BannerFormValues) {
    const payload = buildPayload(values);
    const hasImages = Object.keys(imageFiles).length > 0;
    if (isNew) {
      createBanner(
        { data: payload, imageFiles: hasImages ? imageFiles : undefined },
        { onSuccess: () => router.back() }
      );
    } else {
      updateBanner(
        { id: bannerId, data: payload, imageFiles: hasImages ? imageFiles : undefined },
        { onSuccess: () => router.back() }
      );
    }
  }

  function handleDelete() {
    showConfirmDialog({
      onConfirm: () => deleteBanner(bannerId, { onSuccess: () => router.back() }),
    });
  }

  if (!isNew && isLoading) return <LoadingSpinner />;
  if (!isNew && isError) {
    return <ErrorView message="Banner yüklenemedi." onRetry={() => refetch()} />;
  }

  const isBusy = isCreating || isUpdating || isDeleting;

  return (
    <SafeAreaView style={[styles.safe, { backgroundColor: colors.background }]} edges={['bottom']}>
      <ScrollView contentContainerStyle={styles.scroll} keyboardShouldPersistTaps="handled">
        <BannerFormContent
          form={form}
          isNew={isNew}
          isBusy={isBusy}
          imageUrls={data?.images}
          imageFiles={imageFiles}
          onImageChange={handleImageChange}
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
