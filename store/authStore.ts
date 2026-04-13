// Architectural decision: Zustand v5 with persist middleware using AsyncStorage.
// This gives us hydration-aware auth state that survives app restarts.
// The 'hydrated' flag prevents premature redirects in AuthGuard while
// AsyncStorage is being read on startup.
// Server state (data fetching) is handled by React Query in the API layer.

import { create } from 'zustand';
import { persist, createJSONStorage } from 'zustand/middleware';
import AsyncStorage from '@react-native-async-storage/async-storage';
import type { AuthUser, LoginType } from '../types/auth';

interface AuthLoginData {
  token: string;
  refreshToken: string;
  expiredDate: number;
  user: AuthUser;
  tenantId?: string;
  loginType: LoginType;
}

interface AuthState {
  token: string | null;
  refreshToken: string | null;
  expiredDate: number | null;
  user: AuthUser | null;
  isAuthenticated: boolean;
  tenantId: string | null;
  loginType: LoginType;
  hydrated: boolean;
  login: (data: AuthLoginData) => void;
  logout: () => void;
  setTenant: (tenantId: string) => void;
  updateTokens: (token: string, refreshToken: string, expiredDate: number) => void;
  setHydrated: () => void;
}

export const useAuthStore = create<AuthState>()(
  persist(
    (set) => ({
      token: null,
      refreshToken: null,
      expiredDate: null,
      user: null,
      isAuthenticated: false,
      tenantId: null,
      loginType: 'admin',
      hydrated: false,
      login: (data) =>
        set({
          token: data.token,
          refreshToken: data.refreshToken,
          expiredDate: data.expiredDate,
          user: data.user,
          isAuthenticated: true,
          tenantId: data.tenantId ?? null,
          loginType: data.loginType,
        }),
      logout: () =>
        set({
          token: null,
          refreshToken: null,
          expiredDate: null,
          user: null,
          isAuthenticated: false,
          tenantId: null,
        }),
      setTenant: (tenantId) => set({ tenantId }),
      updateTokens: (token, refreshToken, expiredDate) => set({ token, refreshToken, expiredDate }),
      setHydrated: () => set({ hydrated: true }),
    }),
    {
      name: 'elly-auth-storage',
      storage: createJSONStorage(() => AsyncStorage),
      partialize: (state) => ({
        token: state.token,
        refreshToken: state.refreshToken,
        expiredDate: state.expiredDate,
        user: state.user,
        isAuthenticated: state.isAuthenticated,
        tenantId: state.tenantId,
        loginType: state.loginType,
      }),
      onRehydrateStorage: () => (state, error) => {
        if (!error) {
          state?.setHydrated();
        }
      },
    }
  )
);

const unsub = useAuthStore.persist.onFinishHydration(() => {
  useAuthStore.getState().setHydrated();
  unsub();
});

export type { AuthUser, LoginType };
