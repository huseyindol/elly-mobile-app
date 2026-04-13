import { View, Text, TouchableOpacity, StyleSheet } from 'react-native';
import { useRouter, usePathname } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
import { useAuthStore } from '../../store/authStore';
import { useThemeColor } from '../../hooks/useThemeColor';
import {
  DrawerContentScrollView,
  type DrawerContentComponentProps,
} from '@react-navigation/drawer';

interface MenuItem {
  label: string;
  icon: keyof typeof Ionicons.glyphMap;
  route: string;
}

const menuItems: MenuItem[] = [
  { label: 'Elly Panel', icon: 'grid-outline', route: '/(drawer)/dashboard' },
  { label: 'Sayfalar', icon: 'document-text-outline', route: '/(drawer)/pages' },
  { label: 'Yazılar', icon: 'newspaper-outline', route: '/(drawer)/posts' },
  { label: 'Bannerlar', icon: 'image-outline', route: '/(drawer)/banners' },
  { label: 'Bileşenler', icon: 'cube-outline', route: '/(drawer)/components' },
  { label: "Widget'lar", icon: 'apps-outline', route: '/(drawer)/widgets' },
  { label: 'Dosyalar', icon: 'cloud-upload-outline', route: '/(drawer)/assets' },
  { label: 'Formlar', icon: 'list-outline', route: '/(drawer)/forms' },
  { label: 'İçerikler', icon: 'reader-outline', route: '/(drawer)/contents' },
];

export function DrawerContent(props: DrawerContentComponentProps) {
  const router = useRouter();
  const pathname = usePathname();
  const { logout, user } = useAuthStore();
  const { colors, isDark } = useThemeColor();

  return (
    <View style={[styles.container, { backgroundColor: colors.background }]}>
      <DrawerContentScrollView
        {...props}
        contentContainerStyle={{ backgroundColor: colors.background }}
      >
        {/* User Info Header */}
        <View
          style={[styles.userSection, { backgroundColor: isDark ? colors.surface : '#F9FAFB' }]}
        >
          <View style={styles.avatar}>
            <Text style={styles.avatarText}>{user?.username?.charAt(0).toUpperCase() ?? 'A'}</Text>
          </View>
          <View style={styles.userInfo}>
            <Text style={[styles.username, { color: colors.text }]} numberOfLines={1}>
              {user?.username ?? 'Kullanıcı'}
            </Text>
            <Text style={[styles.email, { color: colors.textSubtle }]} numberOfLines={1}>
              {user?.email ?? ''}
            </Text>
          </View>
        </View>

        <View style={[styles.divider, { backgroundColor: colors.border }]} />

        {/* Menu Items */}
        <View style={styles.menuList}>
          {menuItems.map((item) => {
            const isActive = pathname.startsWith(item.route.replace('/(drawer)', ''));
            return (
              <TouchableOpacity
                key={item.route}
                style={[
                  styles.menuItem,
                  isActive && [
                    styles.menuItemActive,
                    { backgroundColor: isDark ? colors.surface : '#EEF2FF' },
                  ],
                ]}
                onPress={() => router.push(item.route as `/${string}`)}
                activeOpacity={0.7}
              >
                <Ionicons
                  name={item.icon}
                  size={22}
                  color={isActive ? colors.primary[600] : colors.icon}
                  style={styles.menuIcon}
                />
                <Text
                  style={[
                    styles.menuLabel,
                    { color: colors.text },
                    isActive && [styles.menuLabelActive, { color: colors.primary[600] }],
                  ]}
                >
                  {item.label}
                </Text>
              </TouchableOpacity>
            );
          })}

          <View style={[styles.divider, { backgroundColor: colors.border }]} />

          {/* Settings */}
          <TouchableOpacity
            style={[
              styles.menuItem,
              pathname.includes('settings') && {
                backgroundColor: isDark ? colors.surface : '#EEF2FF',
              },
            ]}
            onPress={() => router.push('/(drawer)/settings')}
            activeOpacity={0.7}
          >
            <Ionicons
              name="settings-outline"
              size={22}
              color={colors.icon}
              style={styles.menuIcon}
            />
            <Text style={[styles.menuLabel, { color: colors.text }]}>Ayarlar</Text>
          </TouchableOpacity>
        </View>
      </DrawerContentScrollView>

      {/* Logout */}
      <View style={[styles.footer, { borderTopColor: colors.border }]}>
        <TouchableOpacity style={styles.logoutButton} onPress={logout} activeOpacity={0.7}>
          <Ionicons name="log-out-outline" size={22} color={colors.danger} />
          <Text style={[styles.logoutText, { color: colors.danger }]}>Çıkış Yap</Text>
        </TouchableOpacity>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1 },
  userSection: { flexDirection: 'row', padding: 20, alignItems: 'center' },
  avatar: {
    width: 48,
    height: 48,
    borderRadius: 24,
    backgroundColor: '#4F46E5',
    justifyContent: 'center',
    alignItems: 'center',
    marginRight: 12,
  },
  avatarText: { color: '#fff', fontSize: 20, fontWeight: '700' },
  userInfo: { flex: 1 },
  username: { fontSize: 15, fontWeight: '700' },
  email: { fontSize: 12, marginTop: 1 },
  divider: { height: 1, marginVertical: 8 },
  menuList: { paddingHorizontal: 12, paddingTop: 8 },
  menuItem: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingVertical: 12,
    paddingHorizontal: 12,
    borderRadius: 10,
    marginBottom: 2,
  },
  menuItemActive: {},
  menuIcon: { marginRight: 12 },
  menuLabel: { fontSize: 14, fontWeight: '500' },
  menuLabelActive: { fontWeight: '600' },
  footer: { padding: 20, borderTopWidth: 1, paddingBottom: 40 },
  logoutButton: { flexDirection: 'row', alignItems: 'center' },
  logoutText: { fontSize: 15, fontWeight: '600', marginLeft: 12 },
});
