// Dashboard screen — overview of key metrics across all resources.
// StatCard is extracted as a local component to stay within the 150-line limit.

import { View, Text, ScrollView, TouchableOpacity, StyleSheet, RefreshControl } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useRouter } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
import { usePageList } from '../../../hooks/usePages';
import { usePostList } from '../../../hooks/usePosts';
import { useBannerList } from '../../../hooks/useBanners';
import { useComponentList } from '../../../hooks/useComponents';
import { useWidgetList } from '../../../hooks/useWidgets';
import { useAuthStore } from '../../../store/authStore';

interface StatCardProps {
  label: string;
  icon: keyof typeof Ionicons.glyphMap;
  color: string;
  bgColor: string;
  count: number;
  isLoading: boolean;
  onPress: () => void;
}

function StatCard({ label, icon, color, bgColor, count, isLoading, onPress }: StatCardProps) {
  return (
    <TouchableOpacity style={styles.statCard} onPress={onPress} activeOpacity={0.8}>
      <View style={[styles.statIcon, { backgroundColor: bgColor }]}>
        <Ionicons name={icon} size={22} color={color} />
      </View>
      <Text style={styles.statCount}>{isLoading ? '—' : count}</Text>
      <Text style={styles.statLabel}>{label}</Text>
    </TouchableOpacity>
  );
}

const QUICK_LINKS = [
  { label: 'Dosyalar', icon: 'cloud-upload-outline' as const, route: '/(drawer)/assets' as const },
  { label: 'Formlar', icon: 'list-outline' as const, route: '/(drawer)/forms' as const },
  { label: 'İçerikler', icon: 'reader-outline' as const, route: '/(drawer)/contents' as const },
];

export default function DashboardScreen() {
  const router = useRouter();
  const { user } = useAuthStore();

  const { data: pages, isLoading: pLoading, refetch: refetchPages } = usePageList();
  const { data: posts, isLoading: poLoading, refetch: refetchPosts } = usePostList();
  const { data: banners, isLoading: bLoading, refetch: refetchBanners } = useBannerList();
  const { data: components, isLoading: cLoading, refetch: refetchComponents } = useComponentList();
  const { data: widgets, isLoading: wLoading, refetch: refetchWidgets } = useWidgetList();

  const isRefreshing = pLoading || poLoading || bLoading || cLoading || wLoading;

  const onRefresh = () => {
    void refetchPages();
    void refetchPosts();
    void refetchBanners();
    void refetchComponents();
    void refetchWidgets();
  };

  // API returns { result, data: [...] } — access .data for the array
  const pageCount = Array.isArray(pages?.data) ? pages.data.length : 0;
  const postCount = Array.isArray(posts?.data) ? posts.data.length : 0;
  const bannerCount = Array.isArray(banners?.data) ? banners.data.length : 0;
  const componentCount = Array.isArray(components?.data) ? components.data.length : 0;
  const widgetCount = Array.isArray(widgets?.data) ? widgets.data.length : 0;

  return (
    <SafeAreaView style={styles.safe} edges={['bottom']}>
      <ScrollView
        contentContainerStyle={styles.scroll}
        refreshControl={
          <RefreshControl refreshing={isRefreshing} onRefresh={onRefresh} tintColor="#4F46E5" />
        }
      >
        <View style={styles.welcomeRow}>
          <Text style={styles.welcome}>Hoş geldin,</Text>
          <Text style={styles.username}>{user?.username ?? 'Admin'} 👋</Text>
        </View>

        <Text style={styles.sectionTitle}>Genel Bakış</Text>
        <View style={styles.grid}>
          <StatCard label="Sayfalar" icon="document-text-outline" color="#4F46E5" bgColor="#EEF2FF" count={pageCount} isLoading={pLoading} onPress={() => router.push('/(drawer)/pages')} />
          <StatCard label="Yazılar" icon="newspaper-outline" color="#059669" bgColor="#ECFDF5" count={postCount} isLoading={poLoading} onPress={() => router.push('/(drawer)/posts')} />
          <StatCard label="Bannerlar" icon="image-outline" color="#D97706" bgColor="#FFFBEB" count={bannerCount} isLoading={bLoading} onPress={() => router.push('/(drawer)/banners')} />
          <StatCard label="Bileşenler" icon="cube-outline" color="#7C3AED" bgColor="#F5F3FF" count={componentCount} isLoading={cLoading} onPress={() => router.push('/(drawer)/components')} />
          <StatCard label="Widget'lar" icon="apps-outline" color="#DB2777" bgColor="#FDF2F8" count={widgetCount} isLoading={wLoading} onPress={() => router.push('/(drawer)/widgets')} />
        </View>

        <Text style={styles.sectionTitle}>Hızlı Erişim</Text>
        <View style={styles.quickLinks}>
          {QUICK_LINKS.map((item) => (
            <TouchableOpacity
              key={item.route}
              style={styles.quickLink}
              onPress={() => router.push(item.route)}
              activeOpacity={0.8}
            >
              <Ionicons name={item.icon} size={20} color="#6B7280" />
              <Text style={styles.quickLabel}>{item.label}</Text>
              <Ionicons name="chevron-forward" size={16} color="#D1D5DB" />
            </TouchableOpacity>
          ))}
        </View>
      </ScrollView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  safe: { flex: 1, backgroundColor: '#F9FAFB' },
  scroll: { padding: 16, paddingBottom: 32 },
  welcomeRow: { marginBottom: 24 },
  welcome: { fontSize: 14, color: '#6B7280' },
  username: { fontSize: 22, fontWeight: '700', color: '#111827', marginTop: 2 },
  sectionTitle: { fontSize: 13, fontWeight: '600', color: '#6B7280', textTransform: 'uppercase', letterSpacing: 0.5, marginBottom: 12, marginTop: 4 },
  grid: { flexDirection: 'row', flexWrap: 'wrap', gap: 12, marginBottom: 24 },
  statCard: { backgroundColor: '#fff', borderRadius: 12, padding: 16, alignItems: 'center', width: '47%', shadowColor: '#000', shadowOffset: { width: 0, height: 1 }, shadowOpacity: 0.06, shadowRadius: 4, elevation: 2 },
  statIcon: { width: 44, height: 44, borderRadius: 22, alignItems: 'center', justifyContent: 'center', marginBottom: 8 },
  statCount: { fontSize: 24, fontWeight: '700', color: '#111827', marginBottom: 2 },
  statLabel: { fontSize: 12, color: '#6B7280', textAlign: 'center' },
  quickLinks: { backgroundColor: '#fff', borderRadius: 12, overflow: 'hidden', shadowColor: '#000', shadowOffset: { width: 0, height: 1 }, shadowOpacity: 0.06, shadowRadius: 4, elevation: 2 },
  quickLink: { flexDirection: 'row', alignItems: 'center', paddingHorizontal: 16, paddingVertical: 14, borderBottomWidth: 1, borderBottomColor: '#F3F4F6', gap: 12 },
  quickLabel: { flex: 1, fontSize: 15, color: '#374151' },
});
