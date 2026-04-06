// Elly Mobile App — New page screen
// Standalone create form. Mirrors [id].tsx with isNew=true always.
// Kept separate so Expo Router can resolve /pages/new without ambiguity.

import { ScrollView, StyleSheet, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useRouter } from 'expo-router';
import { useForm, Controller } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { useCreatePage } from '../../../hooks/usePages';
import { PageFormContent } from '../../../components/forms/PageFormContent';
import { pageSchema } from './[id]';
import type { PageFormValues } from './[id]';
import type { PageFormData } from '../../../types/page';

export default function NewPageScreen() {
  const router = useRouter();
  const { mutate: createPage, isPending } = useCreatePage();

  const form = useForm<PageFormValues>({
    resolver: zodResolver(pageSchema),
    defaultValues: { status: true, noIndex: false, noFollow: false },
  });

  function onSubmit(values: PageFormValues) {
    const payload: PageFormData = {
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
    createPage(payload, { onSuccess: () => router.back() });
  }

  return (
    <SafeAreaView style={styles.safe} edges={['bottom']}>
      <ScrollView contentContainerStyle={styles.scroll} keyboardShouldPersistTaps="handled">
        <PageFormContent
          form={form}
          isNew
          isBusy={isPending}
          onSubmit={onSubmit}
          onDelete={() => undefined}
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
