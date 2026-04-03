// Architectural decision: Auth mutations live in a dedicated hook rather than being
// co-located with the Zustand store. This keeps the store thin (client state only)
// and lets React Query manage the async lifecycle (loading, error) of login/logout
// API calls. The Zustand store is updated in onSuccess callbacks so the rest of the
// app reactively picks up the new auth state.

import { useMutation } from '@tanstack/react-query';
import { authService, type LoginCredentials, type LoginResponse } from '../services/auth';
import { useAuthStore, type AuthUser } from '../store/authStore';

export const useLogin = () => {
  const login = useAuthStore((state: { login: (token: string, user: AuthUser) => void }) => state.login);
  return useMutation({
    mutationFn: (credentials: LoginCredentials) =>
      authService.login(credentials).then((res) => res.data),
    onSuccess: (data: LoginResponse) => {
      login(data.token, data.user);
    },
  });
};

export const useLogout = () => {
  const logout = useAuthStore((state: { logout: () => void }) => state.logout);
  return useMutation({
    mutationFn: () => authService.logout().then((res) => res.data),
    onSuccess: () => {
      logout();
    },
    onError: () => {
      // Clear local auth state even if the server-side logout call fails so
      // the user is never stuck in an authenticated-but-broken state.
      logout();
    },
  });
};
