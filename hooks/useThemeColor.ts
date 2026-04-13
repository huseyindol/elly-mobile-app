import { useColorScheme } from 'react-native';
import { COLORS } from '../constants/theme';
import { useThemeStore } from '../store/themeStore';

export function useThemeColor() {
  const systemScheme = useColorScheme() ?? 'light';
  const { themeMode } = useThemeStore();

  // Resolve the active scheme based on user preference
  const resolvedScheme = themeMode === 'system' ? systemScheme : themeMode;

  return {
    colors: COLORS[resolvedScheme],
    isDark: resolvedScheme === 'dark',
    themeMode,
  };
}
