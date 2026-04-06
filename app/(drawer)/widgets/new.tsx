// Elly Mobile App — New Widget screen
// Standalone create form. Mirrors [id].tsx with isNew=true always.

import { ScrollView, StyleSheet, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useRouter } from 'expo-router';
import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { useCreateWidget } from '../../../hooks/useWidgets';
import { WidgetFormContent } from '../../../components/forms/WidgetFormContent';
import { widgetSchema } from './[id]';
import type { WidgetFormValues } from './[id]';
import type { WidgetFormData } from '../../../types/widget';

export default function NewWidgetScreen() {
  const router = useRouter();
  const { mutate: createWidget, isPending } = useCreateWidget();

  const form = useForm<WidgetFormValues>({
    resolver: zodResolver(widgetSchema),
    defaultValues: { status: true, orderIndex: 0, type: 'BANNER' },
  });

  function onSubmit(values: WidgetFormValues) {
    const payload: WidgetFormData = {
      name: values.name,
      description: values.description,
      type: values.type,
      content: values.content,
      orderIndex: values.orderIndex,
      status: values.status,
      template: values.template,
    };
    createWidget(payload, { onSuccess: () => router.back() });
  }

  return (
    <SafeAreaView style={styles.safe} edges={['bottom']}>
      <ScrollView contentContainerStyle={styles.scroll} keyboardShouldPersistTaps="handled">
        <WidgetFormContent
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
