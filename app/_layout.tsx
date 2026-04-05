// Root layout — application entry point.
// Architectural decisions:
//   1. QueryClientProvider wraps the entire app for React Query server state.
//   2. SafeAreaProvider wraps the entire app for safe area insets on all screens.
//   3. Auth guard uses Zustand useAuthStore; unauthenticated users are redirected
//      to /(auth)/login before any tabs render.
//   4. SplashScreen is kept visible until the layout is ready to avoid flash.
//   5. AuthGuard waits for Zustand AsyncStorage rehydration ('hydrated' flag)
//      before performing any redirects to prevent spurious login redirects on launch.

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
  const { isAuthenticated, hydrated } = useAuthStore();
  const segments = useSegments();
  const router = useRouter();

  useEffect(() => {
    if (!hydrated) return; // Wait for rehydration
    SplashScreen.hideAsync();
  }, [hydrated]);

  useEffect(() => {
    if (!hydrated) return; // Wait for rehydration

    const inAuthGroup = segments[0] === '(auth)';
    if (!isAuthenticated && !inAuthGroup) {
      router.replace('/(auth)/login');
    } else if (isAuthenticated && inAuthGroup) {
      router.replace('/(tabs)/dashboard');
    }
  }, [isAuthenticated, hydrated, segments]);

  if (!hydrated) {
    return null; // Keep splash screen visible during rehydration
  }

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
