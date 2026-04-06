// Elly Mobile App — BannerImagePicker
// Single image slot picker for banner create/edit screens.
// Shows existing URL or locally picked image; triggers expo-image-picker on press.

import { useState } from 'react';
import { View, Text, Image, TouchableOpacity, ActivityIndicator, Alert, StyleSheet } from 'react-native';
import * as ImagePicker from 'expo-image-picker';
import { Ionicons } from '@expo/vector-icons';

export interface PickedImage {
  uri: string;
  type: string;
  name: string;
}

interface BannerImagePickerProps {
  label: string;
  existingUri?: string;
  value: PickedImage | null;
  onChange: (file: PickedImage | null) => void;
}

export function BannerImagePicker({ label, existingUri, value, onChange }: BannerImagePickerProps) {
  const [loading, setLoading] = useState(false);
  const displayUri = value?.uri ?? existingUri;

  async function pick() {
    const { status } = await ImagePicker.requestMediaLibraryPermissionsAsync();
    if (status !== 'granted') {
      Alert.alert('İzin Gerekli', 'Fotoğraf kütüphanesine erişim izni verilmedi.');
      return;
    }
    setLoading(true);
    try {
      const result = await ImagePicker.launchImageLibraryAsync({
        mediaTypes: ['images'],
        allowsEditing: false,
        quality: 0.85,
      });
      if (!result.canceled && result.assets[0]) {
        const asset = result.assets[0];
        const uri = asset.uri;
        const ext = uri.split('.').pop() ?? 'jpg';
        const name = asset.fileName ?? `banner-${label.toLowerCase()}-${Date.now()}.${ext}`;
        const type = asset.mimeType ?? `image/${ext}`;
        onChange({ uri, type, name });
      }
    } finally {
      setLoading(false);
    }
  }

  return (
    <View style={styles.slot}>
      <View style={styles.slotHeader}>
        <Text style={styles.slotLabel}>{label}</Text>
        {value && (
          <TouchableOpacity onPress={() => onChange(null)} hitSlop={{ top: 8, bottom: 8, left: 8, right: 8 }}>
            <Text style={styles.clearBtn}>Kaldır</Text>
          </TouchableOpacity>
        )}
      </View>

      <TouchableOpacity style={styles.imageArea} onPress={pick} activeOpacity={0.85} disabled={loading}>
        {loading ? (
          <ActivityIndicator color="#4F46E5" />
        ) : displayUri ? (
          <>
            <Image source={{ uri: displayUri }} style={styles.preview} resizeMode="cover" />
            <View style={styles.changeOverlay}>
              <Ionicons name="camera-outline" size={18} color="#fff" />
              <Text style={styles.changeText}>Değiştir</Text>
            </View>
          </>
        ) : (
          <View style={styles.emptySlot}>
            <Ionicons name="image-outline" size={32} color="#D1D5DB" />
            <Text style={styles.emptyText}>Resim Seç</Text>
          </View>
        )}
      </TouchableOpacity>

      {value && (
        <Text style={styles.pickedName} numberOfLines={1}>{value.name}</Text>
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  slot: { marginBottom: 16 },
  slotHeader: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', marginBottom: 6 },
  slotLabel: { fontSize: 13, fontWeight: '600', color: '#374151' },
  clearBtn: { fontSize: 13, color: '#EF4444', fontWeight: '500' },
  imageArea: {
    width: '100%', height: 120, borderRadius: 10, overflow: 'hidden',
    borderWidth: 1, borderColor: '#E5E7EB',
    backgroundColor: '#F9FAFB',
  },
  preview: { width: '100%', height: '100%' },
  changeOverlay: {
    position: 'absolute', bottom: 0, left: 0, right: 0,
    backgroundColor: 'rgba(0,0,0,0.45)', flexDirection: 'row',
    alignItems: 'center', justifyContent: 'center', gap: 4, paddingVertical: 6,
  },
  changeText: { fontSize: 13, color: '#fff', fontWeight: '600' },
  emptySlot: { flex: 1, alignItems: 'center', justifyContent: 'center', gap: 6 },
  emptyText: { fontSize: 13, color: '#9CA3AF' },
  pickedName: { fontSize: 11, color: '#6B7280', marginTop: 4 },
});
