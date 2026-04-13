// Elly Mobile App — New post screen
// Standalone create form. Mirrors [id].tsx with isNew=true always.
// Kept separate so Expo Router can resolve /posts/new without ambiguity.

import { ScrollView, StyleSheet, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useRouter } from 'expo-router';
import { useThemeColor } from '../../../hooks/useThemeColor';
import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { useCreatePost } from '../../../hooks/usePosts';
import { PostFormContent } from '../../../components/forms/PostFormContent';
import { postSchema } from './[id]';
import type { PostFormValues } from './[id]';
import type { PostFormData } from '../../../types/post';

export default function NewPostScreen() {
  const { colors } = useThemeColor();

  const router = useRouter();
  const { mutate: createPost, isPending } = useCreatePost();

  const form = useForm<PostFormValues>({
    resolver: zodResolver(postSchema),
    defaultValues: { status: true, orderIndex: 0, noIndex: false, noFollow: false },
  });

  function onSubmit(values: PostFormValues) {
    const payload: PostFormData = {
      title: values.title,
      slug: values.slug,
      content: values.content,
      status: values.status,
      orderIndex: values.orderIndex,
      template: values.template,
      seoInfo: {
        title: values.seoTitle ?? '',
        description: values.seoDescription ?? '',
        keywords: values.seoKeywords,
        noIndex: values.noIndex,
        noFollow: values.noFollow,
      },
    };
    createPost(payload, { onSuccess: () => router.back() });
  }

  return (
    <SafeAreaView style={[styles.safe, { backgroundColor: colors.background }]} edges={['bottom']}>
      <ScrollView contentContainerStyle={styles.scroll} keyboardShouldPersistTaps="handled">
        <PostFormContent
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
