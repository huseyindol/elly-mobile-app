import { create } from 'zustand';
import { persist, createJSONStorage } from 'zustand/middleware';
import AsyncStorage from '@react-native-async-storage/async-storage';

export type ThemeMode = 'system' | 'light' | 'dark';

interface ThemeState {
  themeMode: ThemeMode;
  hydrated: boolean;
  setThemeMode: (mode: ThemeMode) => void;
  setHydrated: () => void;
}

export const useThemeStore = create<ThemeState>()(
  persist(
    (set) => ({
      themeMode: 'system',
      hydrated: false,
      setThemeMode: (mode) => set({ themeMode: mode }),
      setHydrated: () => set({ hydrated: true }),
    }),
    {
      name: 'theme-storage',
      storage: createJSONStorage(() => AsyncStorage),
      partialize: (state) => ({
        themeMode: state.themeMode,
      }),
      onRehydrateStorage: () => (state, error) => {
        if (!error) {
          state?.setHydrated();
        }
      },
    }
  )
);

const unsub = useThemeStore.persist.onFinishHydration(() => {
  useThemeStore.getState().setHydrated();
  unsub();
});
