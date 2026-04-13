import { View, Text, ScrollView, TouchableOpacity, StyleSheet, RefreshControl } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useRouter } from 'expo-router';
import { useThemeColor } from '../../../hooks/useThemeColor';
import { Ionicons } from '@expo/vector-icons';
import { usePageListSummary } from '../../../hooks/usePages';
import { usePostListSummary } from '../../../hooks/usePosts';
import { useBannerListSummary } from '../../../hooks/useBanners';
import { useComponentListSummary } from '../../../hooks/useComponents';
import { useWidgetListSummary } from '../../../hooks/useWidgets';
import { useAuthStore } from '../../../store/authStore';

interface StatCardProps {
  label: string;
  icon: keyof typeof Ionicons.glyphMap;
  color: string;
  bgColor: string;
  borderColor: string;
  count: number;
  isLoading: boolean;
  onPress: () => void;
}

function StatCard({
  label,
  icon,
  color,
  bgColor,
  borderColor,
  count,
  isLoading,
  onPress,
}: StatCardProps) {
  const { colors } = useThemeColor();
  return (
    <TouchableOpacity
      style={[styles.statCard, { borderLeftColor: borderColor, backgroundColor: colors.surface }]}
      onPress={onPress}
      activeOpacity={0.7}
    >
      <View style={styles.statCardHeader}>
        <View style={[styles.statIcon, { backgroundColor: bgColor }]}>
          <Ionicons name={icon} size={20} color={color} />
        </View>
        <Text style={[styles.statCount, { color }]}>{isLoading ? '—' : count}</Text>
      </View>
      <Text style={[styles.statLabel, { color: colors.textSubtle }]}>{label}</Text>
    </TouchableOpacity>
  );
}

const QUICK_LINKS = [
  {
    label: 'Dosyalar',
    icon: 'cloud-upload-outline' as const,
    route: '/(drawer)/assets' as const,
    color: '#0EA5E9',
    bg: '#F0F9FF',
  },
  {
    label: 'Formlar',
    icon: 'list-outline' as const,
    route: '/(drawer)/forms' as const,
    color: '#8B5CF6',
    bg: '#F5F3FF',
  },
  {
    label: 'İçerikler',
    icon: 'reader-outline' as const,
    route: '/(drawer)/contents' as const,
    color: '#F97316',
    bg: '#FFF7ED',
  },
];

export default function DashboardScreen() {
  const { colors } = useThemeColor();

  const router = useRouter();
  const { user } = useAuthStore();

  const { data: pages, isLoading: pLoading, refetch: refetchPages } = usePageListSummary();
  const { data: posts, isLoading: poLoading, refetch: refetchPosts } = usePostListSummary();
  const { data: banners, isLoading: bLoading, refetch: refetchBanners } = useBannerListSummary();
  const {
    data: components,
    isLoading: cLoading,
    refetch: refetchComponents,
  } = useComponentListSummary();
  const { data: widgets, isLoading: wLoading, refetch: refetchWidgets } = useWidgetListSummary();

  const isRefreshing = pLoading || poLoading || bLoading || cLoading || wLoading;

  const onRefresh = () => {
    void refetchPages();
    void refetchPosts();
    void refetchBanners();
    void refetchComponents();
    void refetchWidgets();
  };

  const pageCount = Array.isArray(pages?.data) ? pages.data.length : 0;
  const postCount = Array.isArray(posts?.data) ? posts.data.length : 0;
  const bannerCount = Array.isArray(banners?.data) ? banners.data.length : 0;
  const componentCount = Array.isArray(components?.data) ? components.data.length : 0;
  const widgetCount = Array.isArray(widgets?.data) ? widgets.data.length : 0;

  return (
    <SafeAreaView style={[styles.safe, { backgroundColor: colors.background }]} edges={['bottom']}>
      <ScrollView
        contentContainerStyle={styles.scroll}
        refreshControl={
          <RefreshControl refreshing={isRefreshing} onRefresh={onRefresh} tintColor="#4F46E5" />
        }
      >
        {/* Welcome Banner */}
        <View style={styles.welcomeBanner}>
          <View style={styles.welcomeContent}>
            <Text style={styles.welcomeLabel}>Hos geldin,</Text>
            <Text style={styles.welcomeName}>{user?.username ?? 'Admin'}</Text>
            <Text style={styles.welcomeSub}>Yonetim panelinize hos geldiniz</Text>
          </View>
          <View style={styles.welcomeAvatar}>
            <Text style={styles.welcomeAvatarText}>{user?.userCode ?? 'AD'}</Text>
          </View>
        </View>

        {/* Stats */}
        <Text style={[styles.sectionTitle, { color: colors.textSubtle }]}>Genel Bakis</Text>
        <View style={styles.grid}>
          <StatCard
            label="Sayfalar"
            icon="document-text-outline"
            color="#4F46E5"
            bgColor="#EEF2FF"
            borderColor="#4F46E5"
            count={pageCount}
            isLoading={pLoading}
            onPress={() => router.push('/(drawer)/pages')}
          />
          <StatCard
            label="Yazilar"
            icon="newspaper-outline"
            color="#059669"
            bgColor="#ECFDF5"
            borderColor="#059669"
            count={postCount}
            isLoading={poLoading}
            onPress={() => router.push('/(drawer)/posts')}
          />
          <StatCard
            label="Bannerlar"
            icon="image-outline"
            color="#D97706"
            bgColor="#FFFBEB"
            borderColor="#D97706"
            count={bannerCount}
            isLoading={bLoading}
            onPress={() => router.push('/(drawer)/banners')}
          />
          <StatCard
            label="Bilesenler"
            icon="cube-outline"
            color="#7C3AED"
            bgColor="#F5F3FF"
            borderColor="#7C3AED"
            count={componentCount}
            isLoading={cLoading}
            onPress={() => router.push('/(drawer)/components')}
          />
          <StatCard
            label="Widget'lar"
            icon="apps-outline"
            color="#DB2777"
            bgColor="#FDF2F8"
            borderColor="#DB2777"
            count={widgetCount}
            isLoading={wLoading}
            onPress={() => router.push('/(drawer)/widgets')}
          />
        </View>

        {/* Quick Links */}
        <Text style={[styles.sectionTitle, { color: colors.textSubtle }]}>Hizli Erisim</Text>
        <View style={[styles.quickLinks, { backgroundColor: colors.surface }]}>
          {QUICK_LINKS.map((item, idx) => (
            <TouchableOpacity
              key={item.route}
              style={[styles.quickLink, idx === QUICK_LINKS.length - 1 && styles.quickLinkLast]}
              onPress={() => router.push(item.route)}
              activeOpacity={0.7}
            >
              <View style={[styles.quickLinkIcon, { backgroundColor: item.bg }]}>
                <Ionicons name={item.icon} size={18} color={item.color} />
              </View>
              <Text style={[styles.quickLabel, { color: colors.text }]}>{item.label}</Text>
              <Ionicons name="chevron-forward" size={16} color="#D1D5DB" />
            </TouchableOpacity>
          ))}
        </View>
      </ScrollView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  safe: { flex: 1, backgroundColor: '#F3F4F6' },
  scroll: { padding: 16, paddingBottom: 160 },

  welcomeBanner: {
    backgroundColor: '#4F46E5',
    borderRadius: 20,
    padding: 24,
    flexDirection: 'row',
    alignItems: 'center',
    marginBottom: 24,
    shadowColor: '#4F46E5',
    shadowOffset: { width: 0, height: 8 },
    shadowOpacity: 0.3,
    shadowRadius: 16,
    elevation: 8,
  },
  welcomeContent: { flex: 1 },
  welcomeLabel: { fontSize: 14, color: '#C7D2FE', marginBottom: 2 },
  welcomeName: { fontSize: 24, fontWeight: '700', color: '#FFFFFF', marginBottom: 4 },
  welcomeSub: { fontSize: 13, color: '#A5B4FC' },
  welcomeAvatar: {
    width: 52,
    height: 52,
    borderRadius: 26,
    backgroundColor: '#6366F1',
    alignItems: 'center',
    justifyContent: 'center',
    borderWidth: 2,
    borderColor: '#A5B4FC',
  },
  welcomeAvatarText: { fontSize: 18, fontWeight: '700', color: '#FFFFFF' },

  sectionTitle: {
    fontSize: 13,
    fontWeight: '700',
    color: '#6B7280',
    textTransform: 'uppercase',
    letterSpacing: 1,
    marginBottom: 12,
    marginTop: 4,
  },

  grid: { flexDirection: 'row', flexWrap: 'wrap', gap: 12, marginBottom: 28 },
  statCard: {
    backgroundColor: '#FFFFFF',
    borderRadius: 16,
    padding: 16,
    width: '47%',
    borderLeftWidth: 4,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.06,
    shadowRadius: 8,
    elevation: 3,
  },
  statCardHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    marginBottom: 8,
  },
  statIcon: {
    width: 40,
    height: 40,
    borderRadius: 12,
    alignItems: 'center',
    justifyContent: 'center',
  },
  statCount: { fontSize: 28, fontWeight: '800' },
  statLabel: { fontSize: 13, color: '#6B7280', fontWeight: '500' },

  quickLinks: {
    backgroundColor: '#FFFFFF',
    borderRadius: 16,
    overflow: 'hidden',
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.06,
    shadowRadius: 8,
    elevation: 3,
  },
  quickLink: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 16,
    paddingVertical: 16,
    borderBottomWidth: 1,
    borderBottomColor: '#F3F4F6',
    gap: 14,
  },
  quickLinkLast: { borderBottomWidth: 0 },
  quickLinkIcon: {
    width: 36,
    height: 36,
    borderRadius: 10,
    alignItems: 'center',
    justifyContent: 'center',
  },
  quickLabel: { flex: 1, fontSize: 15, color: '#374151', fontWeight: '500' },
});
