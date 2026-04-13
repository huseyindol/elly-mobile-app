// Elly Mobile App — design tokens
// Single source of truth for colors, spacing, typography, and radius.

export const SPACING = {
  0: 0,
  1: 4,
  2: 8,
  3: 12,
  4: 16,
  5: 20,
  6: 24,
  8: 32,
  10: 40,
  12: 48,
  16: 64,
} as const;

export const FONT_SIZES = {
  xs: 12,
  sm: 14,
  base: 16,
  lg: 18,
  xl: 20,
  '2xl': 24,
  '3xl': 30,
  '4xl': 36,
} as const;

export const BORDER_RADIUS = {
  none: 0,
  sm: 4,
  md: 8,
  lg: 12,
  xl: 16,
  '2xl': 24,
  full: 9999,
} as const;

const sharedColors = {
  primary: {
    50: '#eff6ff',
    100: '#dbeafe',
    200: '#bfdbfe',
    300: '#93c5fd',
    400: '#60a5fa',
    500: '#3b82f6', // Brand default
    600: '#2563eb',
    700: '#1d4ed8',
    800: '#1e40af',
    900: '#1e3a8a',
  },
  success: {
    light: '#d1fae5',
    default: '#10b981',
    dark: '#065f46',
  },
  warning: {
    light: '#fef3c7',
    default: '#f59e0b',
    dark: '#78350f',
  },
  error: {
    light: '#fee2e2',
    default: '#ef4444',
    dark: '#7f1d1d',
  },
  info: {
    light: '#dbeafe',
    default: '#3b82f6',
    dark: '#1e3a8a',
  },
  white: '#ffffff',
  black: '#000000',
  transparent: 'transparent',
};

export const COLORS = {
  light: {
    ...sharedColors,
    text: '#111827', // gray-900
    textMuted: '#6B7280', // gray-500
    textSubtle: '#9CA3AF', // gray-400
    background: '#F3F4F6', // gray-100 (App base)
    surface: '#FFFFFF', // white (Cards, Inputs)
    border: '#E5E7EB', // gray-200
    icon: '#6B7280',
    tabBar: '#FFFFFF',
    danger: '#EF4444',
  },
  dark: {
    ...sharedColors,
    text: '#F9FAFB', // gray-50
    textMuted: '#D1D5DB', // gray-300
    textSubtle: '#9CA3AF', // gray-400
    background: '#111827', // gray-900 (App base)
    surface: '#1F2937', // gray-800 (Cards, Inputs)
    border: '#374151', // gray-700
    icon: '#9CA3AF',
    tabBar: '#1F2937',
    danger: '#EF4444',
  },
};
