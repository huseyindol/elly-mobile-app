// Root layout — application entry point.
// Architectural decisions:
//   1. QueryClientProvider wraps the entire app for React Query server state.
//   2. SafeAreaProvider wraps the entire app for safe area insets on all screens.
//   3. Auth guard uses Zustand useAuthStore; unauthenticated users are redirected
//      to /(auth)/login before any tabs render.
//   4. SplashScreen is kept visible until the layout is ready to avoid flash.

import { useEffect } from 'react';
import { Slot, useRouter, useSegments } from 'expo-router';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { SafeAreaProvider } from 'react-native-safe-area-context';
import * as SplashScreen from 'expo-splash-screen';
import { useAuthStore } from '@/store/authStore';

SplashScreen.preventAutoHideAsync();

const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      retry: 2,
      staleTime: 1000 * 60 * 5, // 5 minutes
    },
  },
});

function AuthGuard() {
  const isAuthenticated = useAuthStore((state) => state.isAuthenticated);
  const segments = useSegments();
  const router = useRouter();

  useEffect(() => {
    SplashScreen.hideAsync();
  }, []);

  useEffect(() => {
    const inAuthGroup = segments[0] === '(auth)';

    if (!isAuthenticated && !inAuthGroup) {
      // Not authenticated — send to login
      router.replace('/(auth)/login');
    } else if (isAuthenticated && inAuthGroup) {
      // Already authenticated — send to main app
      router.replace('/(tabs)/dashboard/index');
    }
  }, [isAuthenticated, segments, router]);

  return <Slot />;
}

export default function RootLayout() {
  return (
    <QueryClientProvider client={queryClient}>
      <SafeAreaProvider>
        <AuthGuard />
      </SafeAreaProvider>
    </QueryClientProvider>
  );
}
