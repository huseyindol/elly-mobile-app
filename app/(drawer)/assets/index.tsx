// Elly Mobile App — Assets list screen
// Grid (2-column) view. Both search and subFolder are server-side via useInfiniteAssets.
// Pull-to-refresh resets all pages; infinite scroll loads more.

import { useState, useCallback } from 'react';
import { View, FlatList, TextInput, TouchableOpacity, Text, ScrollView, StyleSheet, RefreshControl, ActivityIndicator } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useRouter } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
import { useInfiniteAssets, useSubFolders } from '../../../hooks/useAssets';
import { AssetCard } from '../../../components/ui/AssetCard';
import { LoadingSpinner } from '../../../components/ui/LoadingSpinner';
import { ErrorView } from '../../../components/ui/ErrorView';
import { EmptyState } from '../../../components/ui/EmptyState';
import type { AssetItem } from '../../../types/asset';

export default function AssetsScreen() {
  const router = useRouter();
  const [search, setSearch] = useState('');
  const [selectedFolder, setSelectedFolder] = useState('all');

  const {
    data,
    isLoading,
    isError,
    refetch,
    fetchNextPage,
    hasNextPage,
    isFetchingNextPage,
    isFetching,
  } = useInfiniteAssets(search || undefined, selectedFolder);

  const { data: foldersData } = useSubFolders();
  const folders = ['all', ...(foldersData?.data ?? [])];

  const assets: AssetItem[] = data?.pages.flatMap((p) => p.data.content) ?? [];

  const handlePress = useCallback((id: number) => {
    router.push(`/(drawer)/assets/${id}` as `/${string}`);
  }, [router]);

  const handleEndReached = useCallback(() => {
    if (hasNextPage && !isFetchingNextPage) {
      void fetchNextPage();
    }
  }, [hasNextPage, isFetchingNextPage, fetchNextPage]);

  if (isLoading) return <LoadingSpinner />;
  if (isError) return <ErrorView message="Dosyalar yüklenemedi." onRetry={() => void refetch()} />;

  return (
    <SafeAreaView style={styles.safe} edges={['bottom']}>
      <View style={styles.searchRow}>
        <Ionicons name="search-outline" size={18} color="#9CA3AF" style={styles.searchIcon} />
        <TextInput style={styles.searchInput} placeholder="Dosya ara..." placeholderTextColor="#9CA3AF" value={search} onChangeText={setSearch} autoCapitalize="none" />
        {search.length > 0 && <TouchableOpacity onPress={() => setSearch('')}><Ionicons name="close-circle" size={18} color="#9CA3AF" /></TouchableOpacity>}
      </View>

      {folders.length > 1 && (
        <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={styles.chips}>
          {folders.map((folder) => (
            <TouchableOpacity key={folder} style={[styles.chip, selectedFolder === folder && styles.chipActive]} onPress={() => setSelectedFolder(folder)}>
              <Text style={[styles.chipText, selectedFolder === folder && styles.chipTextActive]}>{folder === 'all' ? 'Tümü' : folder}</Text>
            </TouchableOpacity>
          ))}
        </ScrollView>
      )}

      <FlatList
        data={assets}
        keyExtractor={(item) => String(item.id)}
        renderItem={({ item }) => <AssetCard asset={item} onPress={() => handlePress(item.id)} />}
        numColumns={2}
        columnWrapperStyle={styles.columnWrapper}
        contentContainerStyle={[styles.list, assets.length === 0 && styles.listEmpty]}
        ListEmptyComponent={
          <EmptyState
            title="Dosya bulunamadı"
            description={search || selectedFolder !== 'all' ? 'Seçilen kriterlere uyan dosya yok.' : 'Henüz dosya yüklenmemiş.'}
            icon="cloud-upload-outline"
          />
        }
        ListFooterComponent={
          isFetchingNextPage ? (
            <ActivityIndicator size="small" color="#4F46E5" style={styles.footer} />
          ) : null
        }
        refreshControl={<RefreshControl refreshing={isFetching && !isLoading && !isFetchingNextPage} onRefresh={() => void refetch()} tintColor="#4F46E5" />}
        onEndReached={handleEndReached}
        onEndReachedThreshold={0.3}
        showsVerticalScrollIndicator={false}
      />

      <TouchableOpacity style={styles.fab} onPress={() => router.push('/(drawer)/assets/new' as `/${string}`)} activeOpacity={0.85}>
        <Ionicons name="cloud-upload-outline" size={24} color="#fff" />
      </TouchableOpacity>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  safe: { flex: 1, backgroundColor: '#F9FAFB' },
  searchRow: { flexDirection: 'row', alignItems: 'center', backgroundColor: '#fff', borderRadius: 12, margin: 16, marginBottom: 8, paddingHorizontal: 12, borderWidth: 1, borderColor: '#E5E7EB' },
  searchIcon: { marginRight: 8 },
  searchInput: { flex: 1, height: 44, fontSize: 15, color: '#111827' },
  chips: { paddingHorizontal: 16, paddingBottom: 8, gap: 8 },
  chip: { paddingHorizontal: 14, paddingVertical: 6, borderRadius: 20, backgroundColor: '#F3F4F6' },
  chipActive: { backgroundColor: '#EEF2FF', borderColor: '#4F46E5', borderWidth: 1 },
  chipText: { fontSize: 13, color: '#6B7280', fontWeight: '500' },
  chipTextActive: { color: '#4F46E5', fontWeight: '600' },
  columnWrapper: { gap: 12, paddingHorizontal: 16 },
  list: { paddingBottom: 100, paddingTop: 4 },
  listEmpty: { flexGrow: 1, justifyContent: 'center' },
  footer: { paddingVertical: 16 },
  fab: { position: 'absolute', bottom: 24, right: 24, width: 56, height: 56, borderRadius: 28, backgroundColor: '#4F46E5', justifyContent: 'center', alignItems: 'center', shadowColor: '#4F46E5', shadowOffset: { width: 0, height: 4 }, shadowOpacity: 0.4, shadowRadius: 8, elevation: 8 },
});
