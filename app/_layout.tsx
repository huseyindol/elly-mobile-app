import { useEffect, useState } from 'react';
import { ActivityIndicator, View } from 'react-native';
import { Slot, useRouter, useSegments } from 'expo-router';
import { StatusBar } from 'expo-status-bar';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { SafeAreaProvider } from 'react-native-safe-area-context';
import { useAuthStore } from '@/store/authStore';
import { useThemeStore } from '../store/themeStore';
import { useThemeColor } from '../hooks/useThemeColor';

const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      retry: 2,
      staleTime: 1000 * 60 * 5,
    },
  },
});

function AuthGuard() {
  const { isAuthenticated, hydrated: authHydrated } = useAuthStore();
  const { hydrated: themeHydrated } = useThemeStore();
  const { colors } = useThemeColor();
  const segments = useSegments();
  const router = useRouter();
  const [ready, setReady] = useState(false);

  useEffect(() => {
    if (authHydrated && themeHydrated) {
      setReady(true);
      return;
    }
    const timeout = setTimeout(() => setReady(true), 1500);
    return () => clearTimeout(timeout);
  }, [authHydrated, themeHydrated]);

  useEffect(() => {
    if (!ready) return;

    const inAuthGroup = segments[0] === '(auth)';
    if (!isAuthenticated && !inAuthGroup) {
      router.replace('/(auth)/login');
    } else if (isAuthenticated && inAuthGroup) {
      router.replace('/(drawer)/dashboard');
    }
  }, [isAuthenticated, ready, segments, router]);

  if (!authHydrated || !themeHydrated || !ready) {
    return (
      <View
        style={{
          flex: 1,
          justifyContent: 'center',
          alignItems: 'center',
          backgroundColor: colors.background,
        }}
      >
        <ActivityIndicator size="large" color={colors.primary[600]} />
      </View>
    );
  }

  return <Slot />;
}

export default function RootLayout() {
  const { isDark } = useThemeColor();

  return (
    <QueryClientProvider client={queryClient}>
      <SafeAreaProvider>
        <StatusBar style={isDark ? 'light' : 'dark'} />
        <AuthGuard />
      </SafeAreaProvider>
    </QueryClientProvider>
  );
}
