// Post detail screen stub — displays a single blog/article post.
// Data fetching and edit form to be wired up by api-agent + ui-agent.

import { View, Text, StyleSheet, ActivityIndicator } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useLocalSearchParams } from 'expo-router';

export default function PostDetailScreen() {
  const { id } = useLocalSearchParams<{ id: string }>();

  return (
    <SafeAreaView style={styles.safe} edges={['bottom']}>
      <View style={styles.container}>
        <Text style={styles.heading}>Yazı Detay</Text>
        <Text style={styles.idLabel}>ID: {id}</Text>
        <View style={styles.loadingWrapper}>
          <ActivityIndicator size="large" color="#4F46E5" />
          <Text style={styles.loadingText}>Yazı yükleniyor...</Text>
        </View>
      </View>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  safe: {
    flex: 1,
    backgroundColor: '#F9FAFB',
  },
  container: {
    flex: 1,
    padding: 20,
  },
  heading: {
    fontSize: 24,
    fontWeight: '700',
    color: '#111827',
    marginBottom: 4,
  },
  idLabel: {
    fontSize: 13,
    color: '#9CA3AF',
    marginBottom: 24,
  },
  loadingWrapper: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    gap: 12,
  },
  loadingText: {
    fontSize: 15,
    color: '#6B7280',
  },
});
