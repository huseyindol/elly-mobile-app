// Elly Mobile App — PostCard component
// Displays a single post row: title, slug, optional content excerpt, order index, status badge, and chevron.

import { View, Text, TouchableOpacity, StyleSheet } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { Badge } from './Badge';
import { formatBooleanStatus } from '../../utils/formatStatus';
import type { PostItem } from '../../types/post';

interface PostCardProps {
  post: PostItem;
  onPress: () => void;
}

export function PostCard({ post, onPress }: PostCardProps) {
  const status = formatBooleanStatus(post.status);

  return (
    <TouchableOpacity style={styles.card} onPress={onPress} activeOpacity={0.7}>
      <View style={styles.row}>
        <View style={styles.info}>
          <Text style={styles.title} numberOfLines={2}>{post.title}</Text>
          <Text style={styles.slug} numberOfLines={1}>/{post.slug}</Text>
          {post.content ? (
            <Text style={styles.excerpt} numberOfLines={2}>{post.content}</Text>
          ) : null}
        </View>
        <View style={styles.right}>
          <Badge label={status.label} variant={status.variant} />
          <Text style={styles.order}>#{post.orderIndex}</Text>
          <Ionicons name="chevron-forward" size={16} color="#D1D5DB" />
        </View>
      </View>
    </TouchableOpacity>
  );
}

const styles = StyleSheet.create({
  card: {
    backgroundColor: '#fff',
    borderRadius: 12,
    padding: 16,
    marginBottom: 10,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 1 },
    shadowOpacity: 0.06,
    shadowRadius: 4,
    elevation: 2,
  },
  row: { flexDirection: 'row', alignItems: 'flex-start' },
  info: { flex: 1, marginRight: 12 },
  title: { fontSize: 15, fontWeight: '600', color: '#111827', marginBottom: 2 },
  slug: { fontSize: 12, color: '#6B7280', fontFamily: 'monospace', marginBottom: 4 },
  excerpt: { fontSize: 13, color: '#9CA3AF', lineHeight: 18 },
  right: { alignItems: 'flex-end', gap: 6 },
  order: { fontSize: 11, color: '#9CA3AF' },
});
