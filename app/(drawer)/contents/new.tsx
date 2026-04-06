// Elly Mobile App — New Content screen
// Standalone create form. Mirrors [id].tsx with isNew=true always.

import { ScrollView, StyleSheet, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useRouter } from 'expo-router';
import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { useCreateContent } from '../../../hooks/useContents';
import { ContentFormContent } from '../../../components/forms/ContentFormContent';
import { contentSchema } from './[id]';
import type { ContentFormValues } from './[id]';
import type { ContentInput } from '../../../types/content';

export default function NewContentScreen() {
  const router = useRouter();
  const { mutate: createContent, isPending } = useCreateContent();

  const form = useForm<ContentFormValues>({
    resolver: zodResolver(contentSchema),
    defaultValues: { isActive: true, sortOrder: 0, metadata: '{}' },
  });

  function onSubmit(values: ContentFormValues) {
    const payload: ContentInput = {
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
    createContent(payload, { onSuccess: () => router.back() });
  }

  return (
    <SafeAreaView style={styles.safe} edges={['bottom']}>
      <ScrollView contentContainerStyle={styles.scroll} keyboardShouldPersistTaps="handled">
        <ContentFormContent
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
