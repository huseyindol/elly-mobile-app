// New post screen stub — form for creating a new blog/article post.
// Form fields and submission to be wired up by api-agent + ui-agent.

import { View, Text, StyleSheet } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';

export default function NewPostScreen() {
  return (
    <SafeAreaView style={styles.safe} edges={['bottom']}>
      <View style={styles.container}>
        <Text style={styles.heading}>Yeni Yazı</Text>
        <Text style={styles.placeholder}>Yeni Yazı oluşturulacak</Text>
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
