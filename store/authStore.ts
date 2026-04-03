// Architectural decision: Zustand is used for client/UI state (auth status, tokens).
// Server state (data fetching) is handled by React Query in the API layer.
// This store is the single source of truth for authentication state across the app.
// token is stored in memory only; for persistence across app restarts, pair with
// AsyncStorage via the zustand persist middleware in a future iteration.

import { create } from 'zustand';

export interface AuthUser {
  id: string;
  email: string;
  name: string;
  role: string;
}

interface AuthState {
  token: string | null;
  isAuthenticated: boolean;
  user: AuthUser | null;
  login: (token: string, user: AuthUser) => void;
  logout: () => void;
}

export const useAuthStore = create<AuthState>()((set) => ({
  token: null,
  isAuthenticated: false,
  user: null,
  login: (token: string, user: AuthUser) =>
    set({ token, user, isAuthenticated: true }),
  logout: () => set({ token: null, user: null, isAuthenticated: false }),
}));
