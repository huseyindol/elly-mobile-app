// Assets list screen stub — displays uploaded files and media.
// List data and navigation to detail screen to be wired up by api-agent + ui-agent.

import { View, Text, StyleSheet } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';

export default function AssetsScreen() {
  return (
    <SafeAreaView style={styles.safe} edges={['bottom']}>
      <View style={styles.container}>
        <Text style={styles.heading}>Dosyalar</Text>
        <Text style={styles.placeholder}>Dosya yönetimi yakında</Text>
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
