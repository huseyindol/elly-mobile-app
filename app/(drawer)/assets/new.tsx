// Elly Mobile App — New Asset screen (upload placeholder)
// File upload functionality will be implemented in Phase 5
// using expo-image-picker and expo-document-picker.

import { View, Text, StyleSheet } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useRouter } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
import { useState } from 'react';
import { Input } from '../../../components/ui/Input';
import { Button } from '../../../components/ui/Button';

export default function NewAssetScreen() {
  const router = useRouter();
  const [subFolder, setSubFolder] = useState('');

  return (
    <SafeAreaView style={styles.safe} edges={['bottom']}>
      <View style={styles.container}>
        <View style={styles.card}>
          <View style={styles.iconWrapper}>
            <Ionicons name="cloud-upload-outline" size={64} color="#4F46E5" />
          </View>
          <Text style={styles.title}>Dosya Yükle</Text>
          <Text style={styles.subtitle}>Dosya yükleme özelliği yakında eklenecektir.</Text>

          <View style={styles.inputWrapper}>
            <Input
              label="Alt Klasör (opsiyonel)"
              value={subFolder}
              onChangeText={setSubFolder}
              placeholder="ornek-klasor"
            />
          </View>

          <Button
            label="Dosya Seç"
            onPress={() => undefined}
            disabled
          />
          <Button
            label="Geri Dön"
            onPress={() => router.back()}
            variant="secondary"
          />
        </View>
      </View>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  safe: { flex: 1, backgroundColor: '#F9FAFB' },
  container: { flex: 1, padding: 16, justifyContent: 'center' },
  card: {
    backgroundColor: '#fff', borderRadius: 16, padding: 24, alignItems: 'center',
    shadowColor: '#000', shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.08, shadowRadius: 8, elevation: 3,
  },
  iconWrapper: { marginBottom: 16 },
  title: { fontSize: 20, fontWeight: '700', color: '#111827', marginBottom: 8 },
  subtitle: { fontSize: 14, color: '#6B7280', textAlign: 'center', lineHeight: 20, marginBottom: 24 },
  inputWrapper: { width: '100%', marginBottom: 16 },
  selectBtn: { width: '100%', marginBottom: 12 },
});
