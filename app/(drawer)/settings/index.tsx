// Settings screen — displays user info and provides logout action.
// Additional settings (theme, language, notifications) to be added by ui-agent.

import { View, Text, TouchableOpacity, StyleSheet, Alert } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useRouter } from 'expo-router';
import { useThemeColor } from '../../../hooks/useThemeColor';
import { useThemeStore } from '../../../store/themeStore';
import type { ThemeMode } from '../../../store/themeStore';
import { Ionicons } from '@expo/vector-icons';
import { useAuthStore } from '../../../store/authStore';

export default function SettingsScreen() {
  const { colors } = useThemeColor();
  const { themeMode, setThemeMode } = useThemeStore();

  const router = useRouter();
  const { user, tenantId, loginType, logout } = useAuthStore();

  const handleLogout = () => {
    Alert.alert('Çıkış Yap', 'Hesabınızdan çıkmak istediğinize emin misiniz?', [
      { text: 'İptal', style: 'cancel' },
      {
        text: 'Çıkış Yap',
        style: 'destructive',
        onPress: () => {
          logout();
          router.replace('/(auth)/login');
        },
      },
    ]);
  };

  return (
    <SafeAreaView style={[styles.safe, { backgroundColor: colors.background }]}>
      <View style={styles.container}>
        {/* User Card */}
        <View style={styles.card}>
          <View style={styles.avatar}>
            <Text style={styles.avatarText}>{user?.username?.charAt(0).toUpperCase() ?? 'A'}</Text>
          </View>
          <Text style={styles.username}>{user?.username ?? '-'}</Text>
          <Text style={styles.email}>{user?.email ?? '-'}</Text>
          {tenantId && <Text style={styles.tenant}>Tenant: {tenantId}</Text>}
          <View style={styles.badge}>
            <Text style={styles.badgeText}>{loginType === 'admin' ? 'Admin' : 'Tenant'}</Text>
          </View>
        </View>

        {/* Theme Settings */}
        <View style={[styles.card, { backgroundColor: colors.surface }]}>
          <Text style={[styles.sectionTitle, { color: colors.text }]}>Tema Ayarları</Text>
          <View style={styles.themeOptions}>
            {(['system', 'light', 'dark'] as ThemeMode[]).map((mode) => {
              const isActive = themeMode === mode;
              return (
                <TouchableOpacity
                  key={mode}
                  style={[
                    styles.themeBtn,
                    { backgroundColor: isActive ? colors.primary[600] : colors.background },
                  ]}
                  onPress={() => setThemeMode(mode)}
                  activeOpacity={0.7}
                >
                  <Text
                    style={[styles.themeBtnText, { color: isActive ? '#fff' : colors.textSubtle }]}
                  >
                    {mode === 'system' ? 'Sistem' : mode === 'light' ? 'Açık' : 'Koyu'}
                  </Text>
                </TouchableOpacity>
              );
            })}
          </View>
        </View>

        {/* Logout */}
        <TouchableOpacity style={styles.logoutBtn} onPress={handleLogout} activeOpacity={0.8}>
          <Ionicons name="log-out-outline" size={20} color="#fff" />
          <Text style={styles.logoutText}>Çıkış Yap</Text>
        </TouchableOpacity>
      </View>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  safe: { flex: 1, backgroundColor: '#F9FAFB' },
  container: { flex: 1, padding: 20 },
  card: {
    backgroundColor: '#fff',
    borderRadius: 16,
    padding: 24,
    alignItems: 'center',
    marginBottom: 24,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.08,
    shadowRadius: 8,
    elevation: 3,
  },
  avatar: {
    width: 72,
    height: 72,
    borderRadius: 36,
    backgroundColor: '#4F46E5',
    justifyContent: 'center',
    alignItems: 'center',
    marginBottom: 12,
  },
  avatarText: { color: '#fff', fontSize: 28, fontWeight: '700' },
  username: { fontSize: 18, fontWeight: '700', color: '#111827', marginBottom: 4 },
  email: { fontSize: 14, color: '#6B7280', marginBottom: 8 },
  tenant: { fontSize: 13, color: '#6366F1', marginBottom: 8 },
  badge: {
    backgroundColor: '#EEF2FF',
    paddingHorizontal: 12,
    paddingVertical: 4,
    borderRadius: 20,
  },
  badgeText: { fontSize: 12, color: '#4F46E5', fontWeight: '600' },
  sectionTitle: { fontSize: 16, fontWeight: '700', marginBottom: 16 },
  themeOptions: { flexDirection: 'row', gap: 12 },
  themeBtn: { flex: 1, paddingVertical: 12, borderRadius: 10, alignItems: 'center' },
  themeBtnText: { fontSize: 14, fontWeight: '600' },
  logoutBtn: {
    backgroundColor: '#EF4444',
    borderRadius: 12,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    padding: 16,
    gap: 8,
  },
  logoutText: { color: '#fff', fontSize: 16, fontWeight: '600' },
});
