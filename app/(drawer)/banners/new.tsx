// Elly Mobile App — New Banner screen
// Standalone create form for a new banner.
// Mirrors [id].tsx but hardcodes isNew=true and skips data fetching.

import { ScrollView, StyleSheet, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useRouter } from 'expo-router';
import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { useCreateBanner } from '../../../hooks/useBanners';
import { showConfirmDialog } from '../../../components/forms/ConfirmDialog';
import { BannerFormContent } from '../../../components/forms/BannerFormContent';
import { bannerSchema } from './[id]';
import type { BannerFormValues } from './[id]';
import type { BannerFormData } from '../../../types/banner';

export default function NewBannerScreen() {
  const router = useRouter();
  const { mutate: createBanner, isPending: isCreating } = useCreateBanner();

  const form = useForm<BannerFormValues>({
    resolver: zodResolver(bannerSchema),
    defaultValues: { status: true, target: '_blank', orderIndex: 0 },
  });

  function onSubmit(values: BannerFormValues) {
    const payload: BannerFormData = {
      title: values.title,
      altText: values.altText,
      link: values.link,
      target: values.target,
      type: values.type,
      orderIndex: values.orderIndex,
      status: values.status,
      subFolder: values.subFolder,
    };
    createBanner({ data: payload }, { onSuccess: () => router.back() });
  }

  function handleDelete() {
    showConfirmDialog({ onConfirm: () => router.back() });
  }

  return (
    <SafeAreaView style={styles.safe} edges={['bottom']}>
      <ScrollView contentContainerStyle={styles.scroll} keyboardShouldPersistTaps="handled">
        <BannerFormContent
          form={form}
          isNew
          isBusy={isCreating}
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
