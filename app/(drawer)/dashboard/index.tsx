// Dashboard screen stub — overview of key metrics.
// Data integration (page count, post count, etc.) to be wired up by api-agent.

import { View, Text, StyleSheet } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';

export default function DashboardScreen() {
  return (
    <SafeAreaView style={styles.safe} edges={['bottom']}>
      <View style={styles.container}>
        <Text style={styles.heading}>Dashboard</Text>
        <Text style={styles.placeholder}>Overview metrics coming soon.</Text>
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
    marginBottom: 8,
  },
  placeholder: {
    fontSize: 15,
    color: '#6B7280',
  },
});
