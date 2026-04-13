// Elly Mobile App — New Form screen
// Standalone form builder for creating a new form schema.

import { useState, useCallback } from 'react';
import { ScrollView, View, Text, StyleSheet, Alert } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useRouter } from 'expo-router';
import { useThemeColor } from '../../../hooks/useThemeColor';
import { useForm, Controller } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { useCreateForm } from '../../../hooks/useForms';
import { FormField as FormFieldComp } from '../../../components/forms/FormField';
import { StatusToggle } from '../../../components/forms/StatusToggle';
import { FormBuilderFieldList } from '../../../components/forms/FormBuilderFieldList';
import { FormBuilderFieldModal } from '../../../components/forms/FormBuilderFieldModal';
import { Button } from '../../../components/ui/Button';
import { formMetaSchema } from './[id]';
import type { FormMetaValues } from './[id]';
import type { FormField, FormSchemaDefinition, FormSchemaFormData } from '../../../types/form';

export default function NewFormScreen() {
  const { colors, isDark } = useThemeColor();

  const router = useRouter();
  const { mutate: createForm, isPending } = useCreateForm();
  const [fields, setFields] = useState<FormField[]>([]);
  const [modalVisible, setModalVisible] = useState(false);
  const [editingField, setEditingField] = useState<FormField | null>(null);

  const form = useForm<FormMetaValues>({
    resolver: zodResolver(formMetaSchema),
    defaultValues: { active: true },
  });

  const handleAddField = useCallback(() => {
    setEditingField(null);
    setModalVisible(true);
  }, []);
  const handleEditField = useCallback((f: FormField) => {
    setEditingField(f);
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
    createForm(payload, { onSuccess: () => router.back() });
  }

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
        <Button label="Oluştur" onPress={form.handleSubmit(onSubmit)} loading={isPending} />
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
  bottomSpacer: { height: 32 },
});
