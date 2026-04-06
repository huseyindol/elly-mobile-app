// Elly Mobile App — Component detail / edit screen
// Handles both editing an existing component (numeric id) and creating a new one (id="new").
// Uses react-hook-form + zod for validation, React Query mutations for persistence.

import { useEffect } from 'react';
import { ScrollView, StyleSheet, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useLocalSearchParams, useRouter } from 'expo-router';
import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { z } from 'zod';
import { useComponent, useCreateComponent, useUpdateComponent, useDeleteComponent } from '../../../hooks/useComponents';
import { LoadingSpinner } from '../../../components/ui/LoadingSpinner';
import { ErrorView } from '../../../components/ui/ErrorView';
import { showConfirmDialog } from '../../../components/forms/ConfirmDialog';
import { ComponentFormContent } from '../../../components/forms/ComponentFormContent';
import type { ComponentFormData } from '../../../types/component';

export const componentSchema = z.object({
  name: z.string().min(1, 'Ad zorunludur').max(100),
  description: z.string().optional(),
  type: z.enum(['BANNER', 'WIDGET', 'FORM']),
  content: z.string().optional(),
  orderIndex: z.coerce.number().int().min(0).default(0),
  status: z.boolean().default(true),
  template: z.string().max(50).optional(),
});

export type ComponentFormValues = z.infer<typeof componentSchema>;

export default function ComponentDetailScreen() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const router = useRouter();
  const isNew = id === 'new';
  const componentId = isNew ? 0 : Number(id);

  const { data, isLoading, isError, refetch } = useComponent(componentId);
  const { mutate: createComponent, isPending: isCreating } = useCreateComponent();
  const { mutate: updateComponent, isPending: isUpdating } = useUpdateComponent();
  const { mutate: deleteComponent, isPending: isDeleting } = useDeleteComponent();

  const form = useForm<ComponentFormValues>({
    resolver: zodResolver(componentSchema),
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
    }
  }, [data, form]);

  function buildPayload(values: ComponentFormValues): ComponentFormData {
    return {
      name: values.name,
      description: values.description,
      type: values.type,
      content: values.content,
      orderIndex: values.orderIndex,
      status: values.status,
      template: values.template,
    };
  }

  function onSubmit(values: ComponentFormValues) {
    const payload = buildPayload(values);
    if (isNew) {
      createComponent(payload, { onSuccess: () => router.back() });
    } else {
      updateComponent({ id: componentId, data: payload }, { onSuccess: () => router.back() });
    }
  }

  function handleDelete() {
    showConfirmDialog({
      onConfirm: () => deleteComponent(componentId, { onSuccess: () => router.back() }),
    });
  }

  if (!isNew && isLoading) return <LoadingSpinner />;
  if (!isNew && isError) {
    return <ErrorView message="Bileşen yüklenemedi." onRetry={() => refetch()} />;
  }

  const isBusy = isCreating || isUpdating || isDeleting;

  return (
    <SafeAreaView style={styles.safe} edges={['bottom']}>
      <ScrollView contentContainerStyle={styles.scroll} keyboardShouldPersistTaps="handled">
        <ComponentFormContent
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
