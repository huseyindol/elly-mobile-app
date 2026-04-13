// Components list screen — server-side search, client-side type chips, infinite scroll, FAB.

import React, { useState, useCallback } from 'react';
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
import { useInfiniteComponents } from '../../../hooks/useComponents';
import { ComponentCard } from '../../../components/ui/ComponentCard';
import { LoadingSpinner } from '../../../components/ui/LoadingSpinner';
import { ErrorView } from '../../../components/ui/ErrorView';
import { EmptyState } from '../../../components/ui/EmptyState';
import { AnimatedFilterChip } from '../../../components/ui/AnimatedFilterChip';
import type { ComponentItem, ComponentType } from '../../../types/component';

type FilterType = 'all' | ComponentType;

const TYPE_FILTERS: FilterType[] = ['all', 'BANNER', 'WIDGET', 'FORM'];
const TYPE_LABELS: Record<FilterType, string> = {
  all: 'Tümü',
  BANNER: 'Banner',
  WIDGET: 'Widget',
  FORM: 'Form',
};

export default function ComponentsScreen() {
  const { colors } = useThemeColor();

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
  } = useInfiniteComponents(search || undefined);

  const allComponents: ComponentItem[] = data?.pages.flatMap((p) => p.data.content) ?? [];

  const filtered =
    selectedType === 'all' ? allComponents : allComponents.filter((c) => c.type === selectedType);

  const handlePress = useCallback(
    (id: number) => {
      router.push(`/(drawer)/components/${id}` as `/${string}`);
    },
    [router]
  );

  const handleEndReached = useCallback(() => {
    if (hasNextPage && !isFetchingNextPage) {
      void fetchNextPage();
    }
  }, [hasNextPage, isFetchingNextPage, fetchNextPage]);

  if (isLoading) return <LoadingSpinner />;
  if (isError)
    return <ErrorView message="Bileşenler yüklenemedi." onRetry={() => void refetch()} />;

  return (
    <SafeAreaView style={[styles.safe, { backgroundColor: colors.background }]} edges={['bottom']}>
      {/* Search */}
      <View style={styles.searchRow}>
        <Ionicons name="search-outline" size={18} color="#9CA3AF" style={styles.searchIcon} />
        <TextInput
          style={styles.searchInput}
          placeholder="Bileşen ara..."
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
      <View style={{ flexGrow: 0, flexShrink: 0, marginBottom: 8 }}>
        <ScrollView
          horizontal
          showsHorizontalScrollIndicator={false}
          contentContainerStyle={styles.chips}
        >
          {TYPE_FILTERS.map((type) => (
            <AnimatedFilterChip
              key={type}
              label={TYPE_LABELS[type]}
              isActive={selectedType === type}
              onPress={() => setSelectedType(type)}
            />
          ))}
        </ScrollView>
      </View>

      <FlatList
        data={filtered}
        keyExtractor={(item) => String(item.id)}
        renderItem={({ item }) => (
          <ComponentCard component={item} onPress={() => handlePress(item.id)} />
        )}
        contentContainerStyle={[styles.list, filtered.length === 0 && styles.listEmpty]}
        ListEmptyComponent={
          <EmptyState
            title="Bileşen bulunamadı"
            description={
              search || selectedType !== 'all'
                ? 'Seçilen kriterlere uyan bileşen yok.'
                : 'Henüz bileşen oluşturulmamış.'
            }
            icon="cube-outline"
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
        onPress={() => router.push('/(drawer)/components/new' as `/${string}`)}
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
