import { View, Text, TouchableOpacity, ScrollView, StyleSheet } from 'react-native';
import { useRouter, usePathname } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
import { useAuthStore } from '../../store/authStore';
import type { DrawerContentComponentProps } from '@react-navigation/drawer';

interface MenuItem {
  label: string;
  icon: keyof typeof Ionicons.glyphMap;
  route: string;
}

const menuItems: MenuItem[] = [
  { label: 'Dashboard', icon: 'grid-outline', route: '/(drawer)/dashboard' },
  { label: 'Sayfalar', icon: 'document-text-outline', route: '/(drawer)/pages' },
  { label: 'Yazılar', icon: 'newspaper-outline', route: '/(drawer)/posts' },
  { label: 'Bannerlar', icon: 'image-outline', route: '/(drawer)/banners' },
  { label: 'Bileşenler', icon: 'cube-outline', route: '/(drawer)/components' },
  { label: "Widget'lar", icon: 'apps-outline', route: '/(drawer)/widgets' },
  { label: 'Dosyalar', icon: 'cloud-upload-outline', route: '/(drawer)/assets' },
  { label: 'Formlar', icon: 'list-outline', route: '/(drawer)/forms' },
  { label: 'İçerikler', icon: 'reader-outline', route: '/(drawer)/contents' },
];

export function DrawerContent(_props: DrawerContentComponentProps) {
  const router = useRouter();
  const pathname = usePathname();
  const { user, tenantId, loginType, logout } = useAuthStore();

  const handleLogout = () => {
    logout();
    router.replace('/(auth)/login');
  };

  return (
    <View style={styles.container}>
      {/* User Info Header */}
      <View style={styles.userSection}>
        <View style={styles.avatar}>
          <Text style={styles.avatarText}>
            {user?.username?.charAt(0).toUpperCase() ?? 'A'}
          </Text>
        </View>
        <View style={styles.userInfo}>
          <Text style={styles.username} numberOfLines={1}>{user?.username ?? 'Kullanıcı'}</Text>
          <Text style={styles.email} numberOfLines={1}>{user?.email ?? ''}</Text>
          {tenantId && (
            <View style={styles.tenantBadge}>
              <Ionicons name="business-outline" size={10} color="#6366F1" />
              <Text style={styles.tenantText}>{tenantId}</Text>
            </View>
          )}
          <Text style={styles.loginTypeBadge}>
            {loginType === 'admin' ? '🔑 Admin' : '🏢 Tenant'}
          </Text>
        </View>
      </View>

      <View style={styles.divider} />

      {/* Menu Items */}
      <ScrollView style={styles.menuList} showsVerticalScrollIndicator={false}>
        {menuItems.map((item) => {
          const isActive = pathname.startsWith(item.route.replace('/(drawer)', ''));
          return (
            <TouchableOpacity
              key={item.route}
              style={[styles.menuItem, isActive && styles.menuItemActive]}
              onPress={() => router.push(item.route as `/${string}`)}
              activeOpacity={0.7}
            >
              <Ionicons
                name={isActive ? (item.icon.replace('-outline', '') as keyof typeof Ionicons.glyphMap) : item.icon}
                size={20}
                color={isActive ? '#4F46E5' : '#6B7280'}
              />
              <Text style={[styles.menuLabel, isActive && styles.menuLabelActive]}>
                {item.label}
              </Text>
            </TouchableOpacity>
          );
        })}

        <View style={styles.divider} />

        {/* Settings */}
        <TouchableOpacity
          style={[styles.menuItem, pathname.includes('settings') && styles.menuItemActive]}
          onPress={() => router.push('/(drawer)/settings')}
          activeOpacity={0.7}
        >
          <Ionicons name="settings-outline" size={20} color="#6B7280" />
          <Text style={styles.menuLabel}>Ayarlar</Text>
        </TouchableOpacity>

        {/* Logout */}
        <TouchableOpacity style={[styles.menuItem, styles.logoutItem]} onPress={handleLogout} activeOpacity={0.7}>
          <Ionicons name="log-out-outline" size={20} color="#EF4444" />
          <Text style={[styles.menuLabel, styles.logoutText]}>Çıkış Yap</Text>
        </TouchableOpacity>
      </ScrollView>
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: '#fff' },
  userSection: { flexDirection: 'row', padding: 20, paddingTop: 60, alignItems: 'center', backgroundColor: '#F9FAFB' },
  avatar: { width: 48, height: 48, borderRadius: 24, backgroundColor: '#4F46E5', justifyContent: 'center', alignItems: 'center', marginRight: 12 },
  avatarText: { color: '#fff', fontSize: 20, fontWeight: '700' },
  userInfo: { flex: 1 },
  username: { fontSize: 15, fontWeight: '700', color: '#111827' },
  email: { fontSize: 12, color: '#6B7280', marginTop: 1 },
  tenantBadge: { flexDirection: 'row', alignItems: 'center', marginTop: 4, gap: 4 },
  tenantText: { fontSize: 11, color: '#6366F1', fontWeight: '500' },
  loginTypeBadge: { fontSize: 11, color: '#9CA3AF', marginTop: 2 },
  divider: { height: 1, backgroundColor: '#F3F4F6', marginVertical: 8 },
  menuList: { flex: 1, paddingHorizontal: 12, paddingTop: 8 },
  menuItem: { flexDirection: 'row', alignItems: 'center', paddingVertical: 12, paddingHorizontal: 12, borderRadius: 10, marginBottom: 2, gap: 12 },
  menuItemActive: { backgroundColor: '#EEF2FF' },
  menuLabel: { fontSize: 14, fontWeight: '500', color: '#374151' },
  menuLabelActive: { color: '#4F46E5', fontWeight: '600' },
  logoutItem: { marginTop: 4 },
  logoutText: { color: '#EF4444' },
});
