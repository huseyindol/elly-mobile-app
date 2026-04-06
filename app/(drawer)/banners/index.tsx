// Banners list screen — search, subFolder filter chips, FlatList with BannerCard, FAB to create.

import { useState, useCallback } from 'react';
import {
  View,
  FlatList,
  TextInput,
  TouchableOpacity,
  Text,
  ScrollView,
  StyleSheet,
  RefreshControl,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useRouter } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
import { useBannerList } from '../../../hooks/useBanners';
import { BannerCard } from '../../../components/ui/BannerCard';
import { LoadingSpinner } from '../../../components/ui/LoadingSpinner';
import { ErrorView } from '../../../components/ui/ErrorView';
import { EmptyState } from '../../../components/ui/EmptyState';
import type { BannerItem } from '../../../types/banner';

export default function BannersScreen() {
  const router = useRouter();
  const [search, setSearch] = useState('');
  const [selectedFolder, setSelectedFolder] = useState<string>('all');
  const { data, isLoading, isError, refetch, isFetching } = useBannerList();

  const banners: BannerItem[] = (data?.data ?? []) as BannerItem[];

  const folders = [
    'all',
    ...Array.from(
      new Set(banners.filter((b) => b.subFolder).map((b) => b.subFolder as string)),
    ),
  ];

  const filtered = banners.filter((b) => {
    const matchFolder = selectedFolder === 'all' || b.subFolder === selectedFolder;
    const matchSearch =
      !search.trim() || b.title.toLowerCase().includes(search.toLowerCase());
    return matchFolder && matchSearch;
  });

  const handlePress = useCallback(
    (id: number) => {
      router.push(`/(drawer)/banners/${id}` as `/${string}`);
    },
    [router],
  );

  if (isLoading) return <LoadingSpinner />;
  if (isError) return <ErrorView message="Bannerlar yüklenemedi." onRetry={() => void refetch()} />;

  return (
    <SafeAreaView style={styles.safe} edges={['bottom']}>
      {/* Search */}
      <View style={styles.searchRow}>
        <Ionicons name="search-outline" size={18} color="#9CA3AF" style={styles.searchIcon} />
        <TextInput
          style={styles.searchInput}
          placeholder="Banner ara..."
          placeholderTextColor="#9CA3AF"
          value={search}
          onChangeText={setSearch}
          autoCapitalize="none"
          autoCorrect={false}
        />
        {search.length > 0 ? (
          <TouchableOpacity onPress={() => setSearch('')}>
            <Ionicons name="close-circle" size={18} color="#9CA3AF" />
          </TouchableOpacity>
        ) : null}
      </View>

      {/* Folder filter chips */}
      {folders.length > 1 ? (
        <ScrollView
          horizontal
          showsHorizontalScrollIndicator={false}
          contentContainerStyle={styles.chips}
        >
          {folders.map((folder) => (
            <TouchableOpacity
              key={folder}
              style={[styles.chip, selectedFolder === folder && styles.chipActive]}
              onPress={() => setSelectedFolder(folder)}
            >
              <Text style={[styles.chipText, selectedFolder === folder && styles.chipTextActive]}>
                {folder === 'all' ? 'Tümü' : folder}
              </Text>
            </TouchableOpacity>
          ))}
        </ScrollView>
      ) : null}

      <FlatList
        data={filtered}
        keyExtractor={(item) => String(item.id)}
        renderItem={({ item }) => (
          <BannerCard banner={item} onPress={() => handlePress(item.id)} />
        )}
        contentContainerStyle={[styles.list, filtered.length === 0 && styles.listEmpty]}
        ListEmptyComponent={
          <EmptyState
            title="Banner bulunamadı"
            description={
              search || selectedFolder !== 'all'
                ? 'Seçilen kriterlere uyan banner yok.'
                : 'Henüz banner oluşturulmamış.'
            }
            icon="image-outline"
          />
        }
        refreshControl={
          <RefreshControl
            refreshing={isFetching && !isLoading}
            onRefresh={() => void refetch()}
            tintColor="#4F46E5"
          />
        }
        showsVerticalScrollIndicator={false}
      />

      <TouchableOpacity
        style={styles.fab}
        onPress={() => router.push('/(drawer)/banners/new' as `/${string}`)}
        activeOpacity={0.85}
      >
        <Ionicons name="add" size={28} color="#fff" />
      </TouchableOpacity>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  safe: { flex: 1, backgroundColor: '#F9FAFB' },
  searchRow: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: '#fff',
    borderRadius: 12,
    margin: 16,
    marginBottom: 8,
    paddingHorizontal: 12,
    borderWidth: 1,
    borderColor: '#E5E7EB',
  },
  searchIcon: { marginRight: 8 },
  searchInput: { flex: 1, height: 44, fontSize: 15, color: '#111827' },
  chips: { paddingHorizontal: 16, paddingBottom: 8, gap: 8 },
  chip: {
    paddingHorizontal: 14,
    paddingVertical: 6,
    borderRadius: 20,
    backgroundColor: '#F3F4F6',
    borderWidth: 1,
    borderColor: 'transparent',
  },
  chipActive: { backgroundColor: '#EEF2FF', borderColor: '#4F46E5' },
  chipText: { fontSize: 13, color: '#6B7280', fontWeight: '500' },
  chipTextActive: { color: '#4F46E5', fontWeight: '600' },
  list: { paddingHorizontal: 16, paddingBottom: 100 },
  listEmpty: { flexGrow: 1, justifyContent: 'center' },
  fab: {
    position: 'absolute',
    bottom: 24,
    right: 24,
    width: 56,
    height: 56,
    borderRadius: 28,
    backgroundColor: '#4F46E5',
    justifyContent: 'center',
    alignItems: 'center',
    shadowColor: '#4F46E5',
    shadowOffset: { width: 0, height: 4 },
    shadowOpacity: 0.4,
    shadowRadius: 8,
    elevation: 8,
  },
});
