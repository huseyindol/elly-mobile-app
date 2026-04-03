// Auth stack layout — wraps all unauthenticated screens (login, forgot-password, etc.)
// Uses expo-router Stack with no visible header for a clean full-screen auth flow.

import { Stack } from 'expo-router';

export default function AuthLayout() {
  return (
    <Stack screenOptions={{ headerShown: false }}>
      <Stack.Screen name="login" />
    </Stack>
  );
}
