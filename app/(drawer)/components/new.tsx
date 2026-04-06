// Elly Mobile App — New Component screen
// Standalone create form. Mirrors [id].tsx with isNew=true always.

import { ScrollView, StyleSheet, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useRouter } from 'expo-router';
import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { useCreateComponent } from '../../../hooks/useComponents';
import { ComponentFormContent } from '../../../components/forms/ComponentFormContent';
import { componentSchema } from './[id]';
import type { ComponentFormValues } from './[id]';
import type { ComponentFormData } from '../../../types/component';

export default function NewComponentScreen() {
  const router = useRouter();
  const { mutate: createComponent, isPending } = useCreateComponent();

  const form = useForm<ComponentFormValues>({
    resolver: zodResolver(componentSchema),
    defaultValues: { status: true, orderIndex: 0, type: 'BANNER' },
  });

  function onSubmit(values: ComponentFormValues) {
    const payload: ComponentFormData = {
      name: values.name,
      description: values.description,
      type: values.type,
      content: values.content,
      orderIndex: values.orderIndex,
      status: values.status,
      template: values.template,
    };
    createComponent(payload, { onSuccess: () => router.back() });
  }

  return (
    <SafeAreaView style={styles.safe} edges={['bottom']}>
      <ScrollView contentContainerStyle={styles.scroll} keyboardShouldPersistTaps="handled">
        <ComponentFormContent
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
