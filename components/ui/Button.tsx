// Elly Mobile App — Button component
// Supports primary/secondary/danger/ghost variants, sm/md/lg sizes,
// loading state, disabled state, and an optional leading icon.

import React from 'react';
import {
  ActivityIndicator,
  Text,
  TouchableOpacity,
  View,
} from 'react-native';
import { Ionicons } from '@expo/vector-icons';

type Variant = 'primary' | 'secondary' | 'danger' | 'ghost';
type Size = 'sm' | 'md' | 'lg';

export interface ButtonProps {
  label: string;
  onPress: () => void;
  variant?: Variant;
  size?: Size;
  loading?: boolean;
  disabled?: boolean;
  icon?: keyof typeof Ionicons.glyphMap;
}

const CONTAINER_CLASSES: Record<Variant, string> = {
  primary: 'bg-blue-600 border border-blue-600',
  secondary: 'bg-white border border-gray-300',
  danger: 'bg-red-600 border border-red-600',
  ghost: 'bg-transparent border border-transparent',
};

const DISABLED_CONTAINER_CLASSES: Record<Variant, string> = {
  primary: 'bg-blue-300 border border-blue-300',
  secondary: 'bg-gray-100 border border-gray-200',
  danger: 'bg-red-300 border border-red-300',
  ghost: 'bg-transparent border border-transparent',
};

const TEXT_CLASSES: Record<Variant, string> = {
  primary: 'text-white font-semibold',
  secondary: 'text-gray-700 font-semibold',
  danger: 'text-white font-semibold',
  ghost: 'text-blue-600 font-semibold',
};

const SIZE_CONTAINER_CLASSES: Record<Size, string> = {
  sm: 'px-3 py-1.5 rounded-md',
  md: 'px-4 py-2.5 rounded-lg',
  lg: 'px-6 py-3.5 rounded-xl',
};

const SIZE_TEXT_CLASSES: Record<Size, string> = {
  sm: 'text-sm',
  md: 'text-base',
  lg: 'text-lg',
};

const ICON_SIZES: Record<Size, number> = { sm: 14, md: 16, lg: 20 };

export function Button({
  label,
  onPress,
  variant = 'primary',
  size = 'md',
  loading = false,
  disabled = false,
  icon,
}: ButtonProps) {
  const isDisabled = disabled || loading;

  const containerClass = [
    'flex-row items-center justify-center',
    SIZE_CONTAINER_CLASSES[size],
    isDisabled ? DISABLED_CONTAINER_CLASSES[variant] : CONTAINER_CLASSES[variant],
  ].join(' ');

  const textClass = [TEXT_CLASSES[variant], SIZE_TEXT_CLASSES[size]].join(' ');
  const iconColor = variant === 'secondary' ? '#374151' : variant === 'ghost' ? '#2563eb' : '#ffffff';

  return (
    <TouchableOpacity
      className={containerClass}
      onPress={onPress}
      disabled={isDisabled}
      activeOpacity={0.75}
    >
      {loading ? (
        <ActivityIndicator
          size="small"
          color={iconColor}
          className="mr-2"
        />
      ) : icon ? (
        <View className="mr-2">
          <Ionicons name={icon} size={ICON_SIZES[size]} color={iconColor} />
        </View>
      ) : null}
      <Text className={textClass}>{label}</Text>
    </TouchableOpacity>
  );
}
