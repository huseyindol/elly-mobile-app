// Widgets list screen — server-side search, client-side type chips (all/BANNER/POST), infinite scroll, FAB.

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
  ActivityIndicator,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useRouter } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
import { useInfiniteWidgets } from '../../../hooks/useWidgets';
import { WidgetCard } from '../../../components/ui/WidgetCard';
import { LoadingSpinner } from '../../../components/ui/LoadingSpinner';
import { ErrorView } from '../../../components/ui/ErrorView';
import { EmptyState } from '../../../components/ui/EmptyState';
import type { WidgetItem, WidgetType } from '../../../types/widget';

type FilterType = 'all' | WidgetType;

const TYPE_FILTERS: FilterType[] = ['all', 'BANNER', 'POST'];
const TYPE_LABELS: Record<FilterType, string> = {
  all: 'Tümü',
  BANNER: 'Banner',
  POST: 'Post',
};

export default function WidgetsScreen() {
  const router = useRouter();
  const [search, setSearch] = useState('');
  const [selectedType, setSelectedType] = useState<FilterType>('all');

  const {
    data,
    isLoading,
    isError,
    refetch,
    fetchNextPage,
    hasNextPage,
    isFetchingNextPage,
    isFetching,
  } = useInfiniteWidgets(search || undefined);

  const allWidgets: WidgetItem[] = data?.pages.flatMap((p) => p.data.content) ?? [];

  const filtered =
    selectedType === 'all'
      ? allWidgets
      : allWidgets.filter((w) => w.type === selectedType);

  const handlePress = useCallback(
    (id: number) => {
      router.push(`/(drawer)/widgets/${id}` as `/${string}`);
    },
    [router],
  );

  const handleEndReached = useCallback(() => {
    if (hasNextPage && !isFetchingNextPage) {
      void fetchNextPage();
    }
  }, [hasNextPage, isFetchingNextPage, fetchNextPage]);

  if (isLoading) return <LoadingSpinner />;
  if (isError) return <ErrorView message="Widget'lar yüklenemedi." onRetry={() => void refetch()} />;

  return (
    <SafeAreaView style={styles.safe} edges={['bottom']}>
      {/* Search */}
      <View style={styles.searchRow}>
        <Ionicons name="search-outline" size={18} color="#9CA3AF" style={styles.searchIcon} />
        <TextInput
          style={styles.searchInput}
          placeholder="Widget ara..."
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

      {/* Type filter chips */}
      <ScrollView
        horizontal
        showsHorizontalScrollIndicator={false}
        contentContainerStyle={styles.chips}
      >
        {TYPE_FILTERS.map((type) => (
          <TouchableOpacity
            key={type}
            style={[styles.chip, selectedType === type && styles.chipActive]}
            onPress={() => setSelectedType(type)}
          >
            <Text style={[styles.chipText, selectedType === type && styles.chipTextActive]}>
              {TYPE_LABELS[type]}
            </Text>
          </TouchableOpacity>
        ))}
      </ScrollView>

      <FlatList
        data={filtered}
        keyExtractor={(item) => String(item.id)}
        renderItem={({ item }) => (
          <WidgetCard widget={item} onPress={() => handlePress(item.id)} />
        )}
        contentContainerStyle={[styles.list, filtered.length === 0 && styles.listEmpty]}
        ListEmptyComponent={
          <EmptyState
            title="Widget bulunamadı"
            description={
              search || selectedType !== 'all'
                ? 'Seçilen kriterlere uyan widget yok.'
                : "Henüz widget oluşturulmamış."
            }
            icon="apps-outline"
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
        onPress={() => router.push('/(drawer)/widgets/new' as `/${string}`)}
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
  footer: { paddingVertical: 16 },
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
