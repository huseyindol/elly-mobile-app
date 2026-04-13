// Elly Mobile App — Form Builder screen
// Edit/create form schemas with a dynamic field builder.
// Top section: title + active toggle (react-hook-form/zod).
// Field list: managed in local state, saved as FormSchemaDefinition.

import { useState, useEffect, useCallback } from 'react';
import { ScrollView, View, Text, StyleSheet, Alert } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useLocalSearchParams, useRouter } from 'expo-router';
import { useThemeColor } from '../../../hooks/useThemeColor';
import { useForm, Controller } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { z } from 'zod';
import {
  useForm as useFormQuery,
  useCreateForm,
  useUpdateForm,
  useDeleteForm,
} from '../../../hooks/useForms';
import { LoadingSpinner } from '../../../components/ui/LoadingSpinner';
import { ErrorView } from '../../../components/ui/ErrorView';
import { FormField as FormFieldComp } from '../../../components/forms/FormField';
import { StatusToggle } from '../../../components/forms/StatusToggle';
import { FormBuilderFieldList } from '../../../components/forms/FormBuilderFieldList';
import { FormBuilderFieldModal } from '../../../components/forms/FormBuilderFieldModal';
import { showConfirmDialog } from '../../../components/forms/ConfirmDialog';
import { Button } from '../../../components/ui/Button';
import type { FormField, FormSchemaDefinition, FormSchemaFormData } from '../../../types/form';

export const formMetaSchema = z.object({
  title: z.string().min(1, 'Başlık zorunludur').max(200),
  active: z.boolean().default(true),
});

export type FormMetaValues = z.infer<typeof formMetaSchema>;

export default function FormDetailScreen() {
  const { colors, isDark } = useThemeColor();

  const { id } = useLocalSearchParams<{ id: string }>();
  const router = useRouter();
  const isNew = id === 'new';
  const formId = isNew ? 0 : Number(id);

  const { data, isLoading, isError, refetch } = useFormQuery(formId);
  const { mutate: createForm, isPending: isCreating } = useCreateForm();
  const { mutate: updateForm, isPending: isUpdating } = useUpdateForm();
  const { mutate: deleteForm, isPending: isDeleting } = useDeleteForm();

  const [fields, setFields] = useState<FormField[]>([]);
  const [modalVisible, setModalVisible] = useState(false);
  const [editingField, setEditingField] = useState<FormField | null>(null);

  const form = useForm<FormMetaValues>({
    resolver: zodResolver(formMetaSchema),
    defaultValues: { active: true },
  });

  useEffect(() => {
    if (data?.data) {
      const d = data.data;
      form.reset({ title: d.title, active: Boolean(d.active) });
      setFields(d.schema?.fields ?? []);
    }
  }, [data, form]);

  const handleAddField = useCallback(() => {
    setEditingField(null);
    setModalVisible(true);
  }, []);

  const handleEditField = useCallback((field: FormField) => {
    setEditingField(field);
    setModalVisible(true);
  }, []);

  const handleDeleteField = useCallback((fieldId: string) => {
    Alert.alert('Alanı Sil', 'Bu alanı silmek istediğinize emin misiniz?', [
      { text: 'İptal', style: 'cancel' },
      {
        text: 'Sil',
        style: 'destructive',
        onPress: () => setFields((prev) => prev.filter((f) => f.id !== fieldId)),
      },
    ]);
  }, []);

  const handleSaveField = useCallback((saved: FormField) => {
    setFields((prev) => {
      const idx = prev.findIndex((f) => f.id === saved.id);
      if (idx >= 0) {
        const next = [...prev];
        next[idx] = saved;
        return next;
      }
      return [...prev, saved];
    });
    setModalVisible(false);
  }, []);

  function onSubmit(values: FormMetaValues) {
    const schema: FormSchemaDefinition = { fields };
    const payload: FormSchemaFormData = { title: values.title, active: values.active, schema };
    if (isNew) {
      createForm(payload, { onSuccess: () => router.back() });
    } else {
      updateForm({ id: formId, data: payload }, { onSuccess: () => router.back() });
    }
  }

  function handleDelete() {
    showConfirmDialog({
      onConfirm: () => deleteForm(formId, { onSuccess: () => router.back() }),
    });
  }

  if (!isNew && isLoading) return <LoadingSpinner />;
  if (!isNew && isError) {
    return <ErrorView message="Form yüklenemedi." onRetry={() => refetch()} />;
  }

  const isBusy = isCreating || isUpdating || isDeleting;

  return (
    <SafeAreaView style={[styles.safe, { backgroundColor: colors.background }]} edges={['bottom']}>
      <ScrollView contentContainerStyle={styles.scroll} keyboardShouldPersistTaps="handled">
        <View
          style={[
            styles.card,
            { backgroundColor: colors.surface, borderColor: isDark ? '#374151' : '#E5E7EB' },
          ]}
        >
          <Text style={[styles.cardTitle, { color: colors.text }]}>Form Bilgileri</Text>
          <FormFieldComp
            control={form.control}
            name="title"
            label="Başlık"
            placeholder="Form başlığı"
          />
          <Controller
            control={form.control}
            name="active"
            render={({ field }) => (
              <StatusToggle value={field.value} onChange={field.onChange} label="Aktif" />
            )}
          />
        </View>

        <FormBuilderFieldList
          fields={fields}
          onEdit={handleEditField}
          onDelete={handleDeleteField}
          onAdd={handleAddField}
        />

        <View style={styles.actions}>
          <Button
            label={isNew ? 'Oluştur' : 'Güncelle'}
            onPress={form.handleSubmit(onSubmit)}
            loading={isBusy}
          />
          {!isNew && (
            <Button label="Sil" onPress={handleDelete} variant="danger" disabled={isBusy} />
          )}
        </View>
        <View style={styles.bottomSpacer} />
      </ScrollView>

      <FormBuilderFieldModal
        visible={modalVisible}
        field={editingField}
        onSave={handleSaveField}
        onClose={() => setModalVisible(false)}
      />
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  safe: { flex: 1, backgroundColor: '#F9FAFB' },
  scroll: { padding: 16 },
  card: {
    backgroundColor: '#fff',
    borderRadius: 12,
    padding: 16,
    marginBottom: 16,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 1 },
    shadowOpacity: 0.05,
    shadowRadius: 4,
    elevation: 2,
  },
  cardTitle: { fontSize: 15, fontWeight: '600', color: '#111827', marginBottom: 12 },
  actions: { gap: 12 },
  bottomSpacer: { height: 32 },
});
