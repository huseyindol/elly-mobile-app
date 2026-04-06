// Elly Mobile App — Asset detail screen
// View-only asset info with image preview (if image type) and delete action.
// Edit is not supported — assets are replaced by re-uploading.

import { View, Text, Image, ScrollView, StyleSheet } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useLocalSearchParams, useRouter } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
import { useAsset, useDeleteAsset } from '../../../hooks/useAssets';
import { LoadingSpinner } from '../../../components/ui/LoadingSpinner';
import { ErrorView } from '../../../components/ui/ErrorView';
import { showConfirmDialog } from '../../../components/forms/ConfirmDialog';
import { Button } from '../../../components/ui/Button';

function InfoRow({ label, value }: { label: string; value: string }) {
  return (
    <View style={styles.infoRow}>
      <Text style={styles.infoLabel}>{label}</Text>
      <Text style={styles.infoValue} numberOfLines={2}>{value}</Text>
    </View>
  );
}

export default function AssetDetailScreen() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const router = useRouter();
  const assetId = Number(id);

  const { data, isLoading, isError, refetch } = useAsset(assetId);
  const { mutate: deleteAsset, isPending: isDeleting } = useDeleteAsset();

  if (isLoading) return <LoadingSpinner />;
  if (isError || !data?.data) {
    return <ErrorView message="Dosya yüklenemedi." onRetry={() => refetch()} />;
  }

  const asset = data.data;
  const isImage = asset.type.startsWith('image/');
  const imageUrl = asset.path;

  function handleDelete() {
    showConfirmDialog({
      title: 'Dosyayı Sil',
      message: `"${asset.name}" dosyasını silmek istediğinize emin misiniz?`,
      onConfirm: () => deleteAsset(assetId, { onSuccess: () => router.back() }),
    });
  }

  return (
    <SafeAreaView style={styles.safe} edges={['bottom']}>
      <ScrollView contentContainerStyle={styles.scroll}>
        {isImage ? (
          <Image source={{ uri: imageUrl }} style={styles.preview} resizeMode="contain" />
        ) : (
          <View style={styles.filePlaceholder}>
            <Ionicons name="document-outline" size={64} color="#9CA3AF" />
            <Text style={styles.fileExt}>.{asset.extension}</Text>
          </View>
        )}

        <View style={styles.card}>
          <Text style={styles.cardTitle}>Dosya Bilgileri</Text>
          <InfoRow label="Ad" value={asset.name} />
          <InfoRow label="Uzantı" value={asset.extension} />
          <InfoRow label="Tür" value={asset.type} />
          {asset.subFolder && <InfoRow label="Alt Klasör" value={asset.subFolder} />}
          <InfoRow label="Yol" value={asset.path} />
        </View>

        <View style={styles.actions}>
          <Button
            label="Yeni Dosya Yükle"
            onPress={() => router.push('/(drawer)/assets/new')}
            variant="secondary"
          />
          <Button
            label="Sil"
            onPress={handleDelete}
            variant="danger"
            loading={isDeleting}
          />
        </View>
        <View style={styles.bottomSpacer} />
      </ScrollView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  safe: { flex: 1, backgroundColor: '#F9FAFB' },
  scroll: { padding: 16 },
  preview: { width: '100%', height: 220, borderRadius: 12, backgroundColor: '#F3F4F6', marginBottom: 16 },
  filePlaceholder: {
    width: '100%', height: 160, borderRadius: 12, backgroundColor: '#F3F4F6',
    alignItems: 'center', justifyContent: 'center', marginBottom: 16, gap: 8,
  },
  fileExt: { fontSize: 16, fontWeight: '700', color: '#6B7280' },
  card: {
    backgroundColor: '#fff', borderRadius: 12, padding: 16, marginBottom: 16,
    shadowColor: '#000', shadowOffset: { width: 0, height: 1 },
    shadowOpacity: 0.05, shadowRadius: 4, elevation: 2,
  },
  cardTitle: { fontSize: 15, fontWeight: '600', color: '#111827', marginBottom: 12 },
  infoRow: {
    flexDirection: 'row', paddingVertical: 8,
    borderBottomWidth: 1, borderBottomColor: '#F3F4F6',
    alignItems: 'flex-start', gap: 12,
  },
  infoLabel: { fontSize: 13, fontWeight: '500', color: '#6B7280', width: 80 },
  infoValue: { fontSize: 13, color: '#111827', flex: 1 },
  actions: { gap: 12 },
  bottomSpacer: { height: 32 },
});
