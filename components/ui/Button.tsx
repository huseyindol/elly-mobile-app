import React from 'react';
import { ActivityIndicator, StyleSheet, Text, TouchableOpacity, View } from 'react-native';
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
  fullWidth?: boolean;
}

const BG: Record<Variant, string> = {
  primary: '#4F46E5',
  secondary: '#FFFFFF',
  danger: '#EF4444',
  ghost: 'transparent',
};

const BG_DISABLED: Record<Variant, string> = {
  primary: '#A5B4FC',
  secondary: '#F3F4F6',
  danger: '#FCA5A5',
  ghost: 'transparent',
};

const BORDER: Record<Variant, string> = {
  primary: '#4F46E5',
  secondary: '#D1D5DB',
  danger: '#EF4444',
  ghost: 'transparent',
};

const TEXT_COLOR: Record<Variant, string> = {
  primary: '#FFFFFF',
  secondary: '#374151',
  danger: '#FFFFFF',
  ghost: '#4F46E5',
};

const HEIGHT: Record<Size, number> = { sm: 36, md: 46, lg: 54 };
const PADDING_H: Record<Size, number> = { sm: 12, md: 20, lg: 28 };
const FONT_SIZE: Record<Size, number> = { sm: 13, md: 15, lg: 17 };
const RADIUS: Record<Size, number> = { sm: 8, md: 12, lg: 16 };
const ICON_SIZE: Record<Size, number> = { sm: 14, md: 18, lg: 22 };

export function Button({
  label,
  onPress,
  variant = 'primary',
  size = 'md',
  loading = false,
  disabled = false,
  icon,
  fullWidth = true,
}: ButtonProps) {
  const isDisabled = disabled || loading;
  const bg = isDisabled ? BG_DISABLED[variant] : BG[variant];
  const textColor = isDisabled && variant !== 'ghost' ? '#FFFFFF' : TEXT_COLOR[variant];
  const iconColor = textColor;

  return (
    <TouchableOpacity
      onPress={onPress}
      disabled={isDisabled}
      activeOpacity={0.75}
      style={[
        styles.base,
        {
          backgroundColor: bg,
          borderColor: isDisabled ? bg : BORDER[variant],
          height: HEIGHT[size],
          paddingHorizontal: PADDING_H[size],
          borderRadius: RADIUS[size],
          alignSelf: fullWidth ? 'stretch' : 'flex-start',
        },
        variant === 'primary' && !isDisabled && styles.primaryShadow,
      ]}
    >
      {loading ? (
        <ActivityIndicator size="small" color={iconColor} style={styles.iconMargin} />
      ) : icon ? (
        <View style={styles.iconMargin}>
          <Ionicons name={icon} size={ICON_SIZE[size]} color={iconColor} />
        </View>
      ) : null}
      <Text style={[styles.label, { color: textColor, fontSize: FONT_SIZE[size] }]}>{label}</Text>
    </TouchableOpacity>
  );
}

const styles = StyleSheet.create({
  base: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    borderWidth: 1,
  },
  primaryShadow: {
    shadowColor: '#4F46E5',
    shadowOffset: { width: 0, height: 4 },
    shadowOpacity: 0.25,
    shadowRadius: 8,
    elevation: 4,
  },
  label: {
    fontWeight: '600',
  },
  iconMargin: {
    marginRight: 8,
  },
});
