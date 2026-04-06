// Elly Mobile App — New Banner screen
// Standalone create form. Mirrors [id].tsx with isNew=true, includes image picking.

import { useState, useCallback } from 'react';
import { ScrollView, StyleSheet, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useRouter } from 'expo-router';
import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { useCreateBanner } from '../../../hooks/useBanners';
import { BannerFormContent } from '../../../components/forms/BannerFormContent';
import type { PickedImage } from '../../../components/forms/BannerImagePicker';
import { bannerSchema } from './[id]';
import type { BannerFormValues } from './[id]';
import type { BannerFormData, BannerImageFiles } from '../../../types/banner';

export default function NewBannerScreen() {
  const router = useRouter();
  const { mutate: createBanner, isPending } = useCreateBanner();
  const [imageFiles, setImageFiles] = useState<BannerImageFiles>({});

  const form = useForm<BannerFormValues>({
    resolver: zodResolver(bannerSchema),
    defaultValues: { status: true, target: '_blank', orderIndex: 0 },
  });

  const handleImageChange = useCallback(
    (slot: keyof BannerImageFiles, file: PickedImage | null) => {
      setImageFiles((prev) => {
        if (file === null) { const next = { ...prev }; delete next[slot]; return next; }
        return { ...prev, [slot]: file };
      });
    },
    [],
  );

  function onSubmit(values: BannerFormValues) {
    const payload: BannerFormData = {
      title: values.title, altText: values.altText, link: values.link,
      target: values.target, type: values.type, orderIndex: values.orderIndex,
      status: values.status, subFolder: values.subFolder,
    };
    const hasImages = Object.keys(imageFiles).length > 0;
    createBanner(
      { data: payload, imageFiles: hasImages ? imageFiles : undefined },
      { onSuccess: () => router.back() },
    );
  }

  return (
    <SafeAreaView style={styles.safe} edges={['bottom']}>
      <ScrollView contentContainerStyle={styles.scroll} keyboardShouldPersistTaps="handled">
        <BannerFormContent
          form={form}
          isNew
          isBusy={isPending}
          imageFiles={imageFiles}
          onImageChange={handleImageChange}
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
