// Elly Mobile App — Badge component
// Color-coded pill badge for status and category labels.

import React from 'react';
import { Text, View } from 'react-native';

type BadgeVariant = 'success' | 'warning' | 'error' | 'info' | 'neutral';

export interface BadgeProps {
  label: string;
  variant?: BadgeVariant;
}

const CONTAINER_CLASSES: Record<BadgeVariant, string> = {
  success: 'bg-emerald-100',
  warning: 'bg-amber-100',
  error: 'bg-red-100',
  info: 'bg-blue-100',
  neutral: 'bg-gray-100',
};

const TEXT_CLASSES: Record<BadgeVariant, string> = {
  success: 'text-emerald-700',
  warning: 'text-amber-700',
  error: 'text-red-700',
  info: 'text-blue-700',
  neutral: 'text-gray-600',
};

export function Badge({ label, variant = 'neutral' }: BadgeProps) {
  return (
    <View className={`px-2.5 py-0.5 rounded-full self-start ${CONTAINER_CLASSES[variant]}`}>
      <Text className={`text-xs font-medium ${TEXT_CLASSES[variant]}`}>
        {label}
      </Text>
    </View>
  );
}
