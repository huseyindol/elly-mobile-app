// Elly Mobile App — Forms list screen
// Server-side search, infinite scroll, pull-to-refresh, FAB.

import { useState, useCallback } from 'react';
import {
  View,
  FlatList,
  TextInput,
  TouchableOpacity,
  StyleSheet,
  RefreshControl,
  ActivityIndicator,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useRouter } from 'expo-router';
import { useThemeColor } from '../../../hooks/useThemeColor';
import { Ionicons } from '@expo/vector-icons';
import { useInfiniteForms } from '../../../hooks/useForms';
import { FormCard } from '../../../components/ui/FormCard';
import { LoadingSpinner } from '../../../components/ui/LoadingSpinner';
import { ErrorView } from '../../../components/ui/ErrorView';
import { EmptyState } from '../../../components/ui/EmptyState';
import type { FormSchema } from '../../../types/form';

export default function FormsScreen() {
  const { colors } = useThemeColor();

  const router = useRouter();
  const [search, setSearch] = useState('');

  const {
    data,
    isLoading,
    isError,
    refetch,
    fetchNextPage,
    hasNextPage,
    isFetchingNextPage,
    isFetching,
  } = useInfiniteForms(search || undefined);

  const forms: FormSchema[] = data?.pages.flatMap((p) => p.data.content) ?? [];

  const handlePress = useCallback(
    (id: number) => {
      router.push(`/(drawer)/forms/${id}` as `/${string}`);
    },
    [router]
  );

  const handleEndReached = useCallback(() => {
    if (hasNextPage && !isFetchingNextPage) {
      void fetchNextPage();
    }
  }, [hasNextPage, isFetchingNextPage, fetchNextPage]);

  if (isLoading) return <LoadingSpinner />;
  if (isError) return <ErrorView message="Formlar yüklenemedi." onRetry={() => void refetch()} />;

  return (
    <SafeAreaView style={[styles.safe, { backgroundColor: colors.background }]} edges={['bottom']}>
      <View style={styles.searchRow}>
        <Ionicons name="search-outline" size={18} color="#9CA3AF" style={styles.searchIcon} />
        <TextInput
          style={styles.searchInput}
          placeholder="Form ara..."
          placeholderTextColor="#9CA3AF"
          value={search}
          onChangeText={setSearch}
          autoCapitalize="none"
        />
        {search.length > 0 && (
          <TouchableOpacity onPress={() => setSearch('')}>
            <Ionicons name="close-circle" size={18} color="#9CA3AF" />
          </TouchableOpacity>
        )}
      </View>

      <FlatList
        data={forms}
        keyExtractor={(item) => String(item.id)}
        renderItem={({ item }) => <FormCard form={item} onPress={() => handlePress(item.id)} />}
        contentContainerStyle={[styles.list, forms.length === 0 && styles.listEmpty]}
        ListEmptyComponent={
          <EmptyState
            title="Form bulunamadı"
            description={
              search ? 'Arama kriterlerine uyan form yok.' : 'Henüz form oluşturulmamış.'
            }
            icon="list-outline"
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
        onPress={() => router.push('/(drawer)/forms/new' as `/${string}`)}
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
    marginBottom: 12,
    paddingHorizontal: 12,
    borderWidth: 1,
    borderColor: '#E5E7EB',
  },
  searchIcon: { marginRight: 8 },
  searchInput: { flex: 1, height: 44, fontSize: 15, color: '#111827' },
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
