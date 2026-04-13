// Elly Mobile App — Post detail / edit screen
// Handles both editing an existing post (numeric id) and creating a new one (id="new").
// Uses react-hook-form + zod for validation, React Query mutations for persistence.

import { useEffect } from 'react';
import { ScrollView, StyleSheet, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useLocalSearchParams, useRouter } from 'expo-router';
import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { z } from 'zod';
import { usePost, useCreatePost, useUpdatePost, useDeletePost } from '../../../hooks/usePosts';
import { useThemeColor } from '../../../hooks/useThemeColor';
import { LoadingSpinner } from '../../../components/ui/LoadingSpinner';
import { ErrorView } from '../../../components/ui/ErrorView';
import { showConfirmDialog } from '../../../components/forms/ConfirmDialog';
import { PostFormContent } from '../../../components/forms/PostFormContent';
import type { PostFormData } from '../../../types/post';

export const postSchema = z.object({
  title: z.string().min(1, 'Başlık zorunludur').max(200, 'Başlık 200 karakteri geçemez'),
  slug: z
    .string()
    .min(1, 'Slug zorunludur')
    .regex(/^[a-z0-9]+(?:-[a-z0-9]+)*$/, 'Slug sadece küçük harf, rakam ve tire içerebilir'),
  content: z.string().optional(),
  status: z.boolean().default(true),
  orderIndex: z.number().int().min(0).default(0),
  template: z.string().max(50).optional(),
  seoTitle: z.string().max(60).optional(),
  seoDescription: z.string().max(160).optional(),
  seoKeywords: z.string().optional(),
  noIndex: z.boolean().default(false),
  noFollow: z.boolean().default(false),
});

export type PostFormValues = z.infer<typeof postSchema>;

export default function PostDetailScreen() {
  const { colors } = useThemeColor();

  const { id } = useLocalSearchParams<{ id: string }>();
  const router = useRouter();
  const isNew = id === 'new';
  const postId = isNew ? 0 : Number(id);

  const { data, isLoading, isError, refetch } = usePost(postId);
  const { mutate: createPost, isPending: isCreating } = useCreatePost();
  const { mutate: updatePost, isPending: isUpdating } = useUpdatePost();
  const { mutate: deletePost, isPending: isDeleting } = useDeletePost();

  const form = useForm<PostFormValues>({
    resolver: zodResolver(postSchema),
    defaultValues: { status: true, orderIndex: 0, noIndex: false, noFollow: false },
  });

  useEffect(() => {
    if (data) {
      form.reset({
        title: data.title,
        slug: data.slug,
        content: data.content ?? '',
        status: Boolean(data.status),
        orderIndex: data.orderIndex ?? 0,
        template: data.template ?? '',
        seoTitle: data.seoInfo?.title ?? '',
        seoDescription: data.seoInfo?.description ?? '',
        seoKeywords: data.seoInfo?.keywords ?? '',
        noIndex: Boolean(data.seoInfo?.noIndex),
        noFollow: Boolean(data.seoInfo?.noFollow),
      });
    }
  }, [data, form]);

  function buildPayload(values: PostFormValues): PostFormData {
    return {
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
  }

  function onSubmit(values: PostFormValues) {
    const payload = buildPayload(values);
    if (isNew) {
      createPost(payload, { onSuccess: () => router.back() });
    } else {
      updatePost({ id: postId, data: payload }, { onSuccess: () => router.back() });
    }
  }

  function handleDelete() {
    showConfirmDialog({
      onConfirm: () => deletePost(postId, { onSuccess: () => router.back() }),
    });
  }

  if (!isNew && isLoading) return <LoadingSpinner />;
  if (!isNew && isError) {
    return <ErrorView message="Yazı yüklenemedi." onRetry={() => refetch()} />;
  }

  const isBusy = isCreating || isUpdating || isDeleting;

  return (
    <SafeAreaView style={[styles.safe, { backgroundColor: colors.background }]} edges={['bottom']}>
      <ScrollView contentContainerStyle={styles.scroll} keyboardShouldPersistTaps="handled">
        <PostFormContent
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
