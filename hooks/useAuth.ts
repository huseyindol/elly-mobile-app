// Architectural decision: Auth mutations live in a dedicated hook rather than being
// co-located with the Zustand store. This keeps the store thin (client state only)
// and lets React Query manage the async lifecycle (loading, error) of login/logout
// API calls. The Zustand store is updated in onSuccess callbacks so the rest of the
// app reactively picks up the new auth state.

import { useMutation } from '@tanstack/react-query';
import { authService } from '../services/auth';
import type { LoginCredentials } from '../types/auth';
import { useAuthStore } from '../store/authStore';

export const useLogin = () =>
  useMutation({
    mutationFn: (credentials: LoginCredentials) =>
      authService.login(credentials).then((res) => res.data),
    onSuccess: (data, credentials) => {
      useAuthStore.getState().login({
        token: data.data.token,
        refreshToken: data.data.refreshToken,
        expiredDate: data.data.expiredDate,
        user: {
          userId: data.data.userId,
          username: data.data.username,
          email: data.data.email,
          userCode: data.data.userCode,
        },
        tenantId: credentials.tenantId,
        loginType: credentials.loginType ?? 'admin',
      });
    },
  });

export const useLogout = () =>
  useMutation({
    mutationFn: () => authService.logout().then((res) => res.data),
    onSuccess: () => {
      useAuthStore.getState().logout();
    },
    onError: () => {
      // Clear local auth state even if the server-side logout call fails so
      // the user is never stuck in an authenticated-but-broken state.
      useAuthStore.getState().logout();
    },
  });
