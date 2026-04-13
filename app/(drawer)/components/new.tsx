// Elly Mobile App — New Component screen
// Standalone create form with relation pickers for banners, widgets, forms.

import { useState, useMemo } from 'react';
import { ScrollView, StyleSheet, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useRouter } from 'expo-router';
import { useThemeColor } from '../../../hooks/useThemeColor';
import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { useCreateComponent } from '../../../hooks/useComponents';
import { useBannerList } from '../../../hooks/useBanners';
import { useWidgetList } from '../../../hooks/useWidgets';
import { useFormList } from '../../../hooks/useForms';
import { ComponentFormContent } from '../../../components/forms/ComponentFormContent';
import { componentSchema } from './[id]';
import type { ComponentFormValues } from './[id]';
import type { ComponentFormData } from '../../../types/component';

export default function NewComponentScreen() {
  const { colors } = useThemeColor();

  const router = useRouter();
  const { mutate: createComponent, isPending } = useCreateComponent();

  const { data: bannersData } = useBannerList();
  const { data: widgetsData } = useWidgetList();
  const { data: formsData } = useFormList();

  const [selectedBannerIds, setSelectedBannerIds] = useState<number[]>([]);
  const [selectedWidgetIds, setSelectedWidgetIds] = useState<number[]>([]);
  const [selectedFormIds, setSelectedFormIds] = useState<number[]>([]);

  const bannerItems = useMemo(
    () =>
      (bannersData?.data ?? []).map((b) => ({ id: b.id, label: b.title, sublabel: b.subFolder })),
    [bannersData]
  );
  const widgetItems = useMemo(
    () => (widgetsData?.data ?? []).map((w) => ({ id: w.id, label: w.name, sublabel: w.type })),
    [widgetsData]
  );
  const formItems = useMemo(
    () =>
      (formsData?.data ?? []).map((f) => ({ id: f.id, label: f.title, sublabel: `v${f.version}` })),
    [formsData]
  );

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
      bannerIds: selectedBannerIds,
      widgetIds: selectedWidgetIds,
      formIds: selectedFormIds,
    };
    createComponent(payload, { onSuccess: () => router.back() });
  }

  return (
    <SafeAreaView style={[styles.safe, { backgroundColor: colors.background }]} edges={['bottom']}>
      <ScrollView contentContainerStyle={styles.scroll} keyboardShouldPersistTaps="handled">
        <ComponentFormContent
          form={form}
          isNew
          isBusy={isPending}
          bannerItems={bannerItems}
          widgetItems={widgetItems}
          formItems={formItems}
          selectedBannerIds={selectedBannerIds}
          selectedWidgetIds={selectedWidgetIds}
          selectedFormIds={selectedFormIds}
          onBannerIdsChange={setSelectedBannerIds}
          onWidgetIdsChange={setSelectedWidgetIds}
          onFormIdsChange={setSelectedFormIds}
          onSubmit={onSubmit}
          onDelete={() => router.back()}
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
