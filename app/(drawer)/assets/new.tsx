// Elly Mobile App — New Asset upload screen
// Supports picking images (expo-image-picker) or any file (expo-document-picker).
// Uploads as multipart/form-data to /assets endpoint via useUploadAsset hook.

import { useState } from 'react';
import {
  View,
  Text,
  Image,
  ScrollView,
  TouchableOpacity,
  ActivityIndicator,
  Alert,
  StyleSheet,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useRouter } from 'expo-router';
import { useThemeColor } from '../../../hooks/useThemeColor';
import * as ImagePicker from 'expo-image-picker';
import * as DocumentPicker from 'expo-document-picker';
import { Ionicons } from '@expo/vector-icons';
import { useUploadAsset, useUploadMultiAssets } from '../../../hooks/useAssets';
import { Input } from '../../../components/ui/Input';
import { Button } from '../../../components/ui/Button';

interface SelectedFile {
  uri: string;
  type: string;
  name: string;
}

function FilePreview({ file }: { file: SelectedFile }) {
  const isImage = file.type.startsWith('image/');
  return (
    <View style={styles.previewWrapper}>
      {isImage ? (
        <Image source={{ uri: file.uri }} style={styles.imagePreview} resizeMode="contain" />
      ) : (
        <View style={styles.filePreview}>
          <Ionicons name="document-outline" size={40} color="#6366F1" />
          <Text style={styles.fileExt}>.{file.name.split('.').pop()}</Text>
        </View>
      )}
      <Text style={styles.fileName} numberOfLines={1}>
        {file.name}
      </Text>
      <Text style={styles.fileType}>{file.type}</Text>
    </View>
  );
}

export default function NewAssetScreen() {
  const { colors } = useThemeColor();

  const router = useRouter();
  const [selectedFiles, setSelectedFiles] = useState<SelectedFile[]>([]);
  const [subFolder, setSubFolder] = useState('');

  const { mutate: uploadSingle, isPending: isUploadingSingle } = useUploadAsset();
  const { mutate: uploadMulti, isPending: isUploadingMulti } = useUploadMultiAssets();
  const isBusy = isUploadingSingle || isUploadingMulti;

  async function pickImage() {
    const { status } = await ImagePicker.requestMediaLibraryPermissionsAsync();
    if (status !== 'granted') {
      Alert.alert('İzin Gerekli', 'Fotoğraf kütüphanesine erişim izni verilmedi.');
      return;
    }
    const result = await ImagePicker.launchImageLibraryAsync({
      mediaTypes: ['images', 'videos'],
      allowsMultipleSelection: true,
      quality: 0.9,
    });
    if (!result.canceled) {
      const files: SelectedFile[] = result.assets.map((a) => {
        const ext = a.uri.split('.').pop() ?? 'jpg';
        return {
          uri: a.uri,
          type: a.mimeType ?? `image/${ext}`,
          name: a.fileName ?? `upload-${Date.now()}.${ext}`,
        };
      });
      setSelectedFiles((prev) => [...prev, ...files]);
    }
  }

  async function pickDocument() {
    const result = await DocumentPicker.getDocumentAsync({
      multiple: true,
      copyToCacheDirectory: true,
    });
    if (!result.canceled) {
      const files: SelectedFile[] = result.assets.map((a) => ({
        uri: a.uri,
        type: a.mimeType ?? 'application/octet-stream',
        name: a.name,
      }));
      setSelectedFiles((prev) => [...prev, ...files]);
    }
  }

  function removeFile(index: number) {
    setSelectedFiles((prev) => prev.filter((_, i) => i !== index));
  }

  function upload() {
    if (selectedFiles.length === 0) return;
    const sf = subFolder.trim() || undefined;

    if (selectedFiles.length === 1) {
      uploadSingle(
        { file: selectedFiles[0], subFolder: sf },
        {
          onSuccess: () => {
            Alert.alert('Başarılı', 'Dosya başarıyla yüklendi.', [
              { text: 'Tamam', onPress: () => router.back() },
            ]);
          },
          onError: () => Alert.alert('Hata', 'Dosya yüklenemedi. Lütfen tekrar deneyin.'),
        }
      );
    } else {
      uploadMulti(
        { files: selectedFiles, subFolder: sf },
        {
          onSuccess: () => {
            Alert.alert('Başarılı', `${selectedFiles.length} dosya başarıyla yüklendi.`, [
              { text: 'Tamam', onPress: () => router.back() },
            ]);
          },
          onError: () => Alert.alert('Hata', 'Dosyalar yüklenemedi. Lütfen tekrar deneyin.'),
        }
      );
    }
  }

  return (
    <SafeAreaView style={[styles.safe, { backgroundColor: colors.background }]} edges={['bottom']}>
      <ScrollView contentContainerStyle={styles.scroll} keyboardShouldPersistTaps="handled">
        {/* Pick buttons */}
        <View style={styles.card}>
          <Text style={styles.cardTitle}>Dosya Seç</Text>
          <View style={styles.pickRow}>
            <TouchableOpacity style={styles.pickBtn} onPress={pickImage} disabled={isBusy}>
              <Ionicons name="image-outline" size={28} color="#4F46E5" />
              <Text style={styles.pickBtnLabel}>Galeri</Text>
              <Text style={styles.pickBtnSub}>Resim / Video</Text>
            </TouchableOpacity>
            <TouchableOpacity style={styles.pickBtn} onPress={pickDocument} disabled={isBusy}>
              <Ionicons name="document-outline" size={28} color="#4F46E5" />
              <Text style={styles.pickBtnLabel}>Dosya</Text>
              <Text style={styles.pickBtnSub}>PDF, ZIP, vb.</Text>
            </TouchableOpacity>
          </View>
        </View>

        {/* Selected files preview */}
        {selectedFiles.length > 0 && (
          <View style={styles.card}>
            <Text style={styles.cardTitle}>Seçilen Dosyalar ({selectedFiles.length})</Text>
            {selectedFiles.map((file, index) => (
              <View key={`${file.uri}-${index}`} style={styles.fileRow}>
                <FilePreview file={file} />
                <TouchableOpacity style={styles.removeBtn} onPress={() => removeFile(index)}>
                  <Ionicons name="trash-outline" size={18} color="#EF4444" />
                </TouchableOpacity>
              </View>
            ))}
          </View>
        )}

        {/* Sub-folder input */}
        <View style={styles.card}>
          <Text style={styles.cardTitle}>Klasör Ayarı</Text>
          <Input
            label="Alt Klasör (opsiyonel)"
            value={subFolder}
            onChangeText={setSubFolder}
            placeholder="ornek-klasor"
          />
        </View>

        {/* Upload & back buttons */}
        <View style={styles.actions}>
          {isBusy ? (
            <View style={styles.uploadingRow}>
              <ActivityIndicator color="#4F46E5" />
              <Text style={styles.uploadingText}>Yükleniyor...</Text>
            </View>
          ) : (
            <Button
              label={
                selectedFiles.length === 0
                  ? 'Dosya Seçilmedi'
                  : `${selectedFiles.length} Dosyayı Yükle`
              }
              onPress={upload}
              disabled={selectedFiles.length === 0}
              icon="cloud-upload-outline"
            />
          )}
          <Button
            label="İptal"
            onPress={() => router.back()}
            variant="secondary"
            disabled={isBusy}
          />
        </View>
      </ScrollView>
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
  pickRow: { flexDirection: 'row', gap: 12 },
  pickBtn: {
    flex: 1,
    alignItems: 'center',
    paddingVertical: 20,
    borderRadius: 12,
    borderWidth: 1.5,
    borderColor: '#E5E7EB',
    borderStyle: 'dashed',
    backgroundColor: '#FAFAFA',
    gap: 4,
  },
  pickBtnLabel: { fontSize: 14, fontWeight: '600', color: '#374151' },
  pickBtnSub: { fontSize: 12, color: '#9CA3AF' },
  fileRow: { flexDirection: 'row', alignItems: 'flex-start', marginBottom: 12 },
  previewWrapper: { flex: 1 },
  imagePreview: { width: '100%', height: 120, borderRadius: 8, backgroundColor: '#F3F4F6' },
  filePreview: {
    width: '100%',
    height: 80,
    borderRadius: 8,
    backgroundColor: '#EEF2FF',
    alignItems: 'center',
    justifyContent: 'center',
    flexDirection: 'row',
    gap: 8,
  },
  fileExt: { fontSize: 14, fontWeight: '700', color: '#4F46E5' },
  fileName: { fontSize: 13, color: '#374151', fontWeight: '500', marginTop: 6 },
  fileType: { fontSize: 11, color: '#9CA3AF', marginTop: 2 },
  removeBtn: { padding: 8, marginLeft: 8 },
  actions: { gap: 12 },
  uploadingRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
    justifyContent: 'center',
    paddingVertical: 14,
  },
  uploadingText: { fontSize: 15, color: '#4F46E5', fontWeight: '500' },
});
