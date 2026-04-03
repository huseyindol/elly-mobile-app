// Elly Mobile App — design tokens
// Single source of truth for colors, spacing, typography, and radius.

export const COLORS = {
  // Brand
  primary: {
    50: '#eff6ff',
    100: '#dbeafe',
    200: '#bfdbfe',
    300: '#93c5fd',
    400: '#60a5fa',
    500: '#3b82f6',
    600: '#2563eb',
    700: '#1d4ed8',
    800: '#1e40af',
    900: '#1e3a8a',
  },

  // Neutrals
  gray: {
    50: '#f9fafb',
    100: '#f3f4f6',
    200: '#e5e7eb',
    300: '#d1d5db',
    400: '#9ca3af',
    500: '#6b7280',
    600: '#4b5563',
    700: '#374151',
    800: '#1f2937',
    900: '#111827',
  },

  // Status
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

  // Surfaces
  white: '#ffffff',
  background: '#f9fafb',
  border: '#e5e7eb',
} as const;

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
