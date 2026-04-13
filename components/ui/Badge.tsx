// Elly Mobile App — Badge component
// Color-coded pill badge for status and category labels.

import { Text, View, StyleSheet } from 'react-native';
import { useThemeColor } from '../../hooks/useThemeColor';

export type BadgeVariant = 'success' | 'warning' | 'error' | 'info' | 'neutral';

export interface BadgeProps {
  label: string;
  variant?: BadgeVariant;
}

export function Badge({ label, variant = 'neutral' }: BadgeProps) {
  const { isDark } = useThemeColor();

  const getVariantStyles = () => {
    switch (variant) {
      case 'success':
        return {
          bg: isDark ? 'rgba(16, 185, 129, 0.15)' : '#d1fae5', // emerald-100
          text: isDark ? '#34d399' : '#047857', // emerald-400 / emerald-700
        };
      case 'warning':
        return {
          bg: isDark ? 'rgba(245, 158, 11, 0.15)' : '#fef3c7', // amber-100
          text: isDark ? '#fbbf24' : '#b45309', // amber-400 / amber-700
        };
      case 'error':
        return {
          bg: isDark ? 'rgba(239, 68, 68, 0.15)' : '#fee2e2', // red-100
          text: isDark ? '#f87171' : '#b91c1c', // red-400 / red-700
        };
      case 'info':
        return {
          bg: isDark ? 'rgba(59, 130, 246, 0.15)' : '#dbeafe', // blue-100
          text: isDark ? '#60a5fa' : '#1d4ed8', // blue-400 / blue-700
        };
      case 'neutral':
      default:
        return {
          bg: isDark ? 'rgba(156, 163, 175, 0.15)' : '#f3f4f6', // gray-100
          text: isDark ? '#d1d5db' : '#4b5563', // gray-300 / gray-600
        };
    }
  };

  const vStyles = getVariantStyles();

  return (
    <View style={[styles.container, { backgroundColor: vStyles.bg }]}>
      <Text style={[styles.text, { color: vStyles.text }]}>{label}</Text>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    paddingHorizontal: 10,
    paddingVertical: 4,
    borderRadius: 9999,
    alignSelf: 'flex-start',
  },
  text: {
    fontSize: 12,
    fontWeight: '600',
  },
});
