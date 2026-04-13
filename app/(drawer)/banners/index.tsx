// Banners list screen — server-side search, client-side subFolder chips, infinite scroll, FAB.

import { useState, useCallback } from 'react';
import {
  View,
  FlatList,
  TextInput,
  TouchableOpacity,
  ScrollView,
  StyleSheet,
  RefreshControl,
  ActivityIndicator,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useRouter } from 'expo-router';
import { useThemeColor } from '../../../hooks/useThemeColor';
import { Ionicons } from '@expo/vector-icons';
import { useInfiniteBanners } from '../../../hooks/useBanners';
import { BannerCard } from '../../../components/ui/BannerCard';
import { LoadingSpinner } from '../../../components/ui/LoadingSpinner';
import { ErrorView } from '../../../components/ui/ErrorView';
import { EmptyState } from '../../../components/ui/EmptyState';
import { AnimatedFilterChip } from '../../../components/ui/AnimatedFilterChip';
import type { BannerItem } from '../../../types/banner';

export default function BannersScreen() {
  const { colors } = useThemeColor();

  const router = useRouter();
  const [search, setSearch] = useState('');
  const [selectedFolder, setSelectedFolder] = useState<string>('all');

  const {
    data,
    isLoading,
    isError,
    refetch,
    fetchNextPage,
    hasNextPage,
    isFetchingNextPage,
    isFetching,
  } = useInfiniteBanners(search || undefined);

  const allBanners: BannerItem[] = data?.pages.flatMap((p) => p.data.content) ?? [];

  const folders = [
    'all',
    ...Array.from(new Set(allBanners.filter((b) => b.subFolder).map((b) => b.subFolder as string))),
  ];

  const filtered =
    selectedFolder === 'all'
      ? allBanners
      : allBanners.filter((b) => b.subFolder === selectedFolder);

  const handlePress = useCallback(
    (id: number) => {
      router.push(`/(drawer)/banners/${id}` as `/${string}`);
    },
    [router]
  );

  const handleEndReached = useCallback(() => {
    if (hasNextPage && !isFetchingNextPage) {
      void fetchNextPage();
    }
  }, [hasNextPage, isFetchingNextPage, fetchNextPage]);

  if (isLoading) return <LoadingSpinner />;
  if (isError) return <ErrorView message="Bannerlar yüklenemedi." onRetry={() => void refetch()} />;

  return (
    <SafeAreaView style={[styles.safe, { backgroundColor: colors.background }]} edges={['bottom']}>
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
        <View style={{ flexGrow: 0, flexShrink: 0, marginBottom: 8 }}>
          <ScrollView
            horizontal
            showsHorizontalScrollIndicator={false}
            contentContainerStyle={styles.chips}
          >
            {folders.map((folder) => (
              <AnimatedFilterChip
                key={folder}
                label={folder === 'all' ? 'Tümü' : folder}
                isActive={selectedFolder === folder}
                onPress={() => setSelectedFolder(folder)}
              />
            ))}
          </ScrollView>
        </View>
      ) : null}

      <FlatList
        data={filtered}
        keyExtractor={(item) => String(item.id)}
        renderItem={({ item }) => <BannerCard banner={item} onPress={() => handlePress(item.id)} />}
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
        ListFooterComponent={
          isFetchingNextPage ? (
            <ActivityIndicator size="small" color="#4F46E5" style={styles.footer} />
          ) : null
        }
        refreshControl={
          <RefreshControl
            refreshing={isFetching && !isLoading && !isFetchingNextPage}
            onRefresh={() => void refetch()}
            tintColor="#4F46E5"
          />
        }
        onEndReached={handleEndReached}
        onEndReachedThreshold={0.3}
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
  chips: { paddingHorizontal: 16, gap: 12, alignItems: 'center', paddingVertical: 8 },
  list: { paddingHorizontal: 16, paddingBottom: 160 },
  listEmpty: { flexGrow: 1, justifyContent: 'center' },
  footer: { paddingVertical: 16 },
  fab: {
    position: 'absolute',
    bottom: 130,
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
