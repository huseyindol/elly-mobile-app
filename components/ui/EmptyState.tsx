// Elly Mobile App — EmptyState component
// Centered icon, title, and optional description for empty list/data views.

import React from 'react';
import { Text, View } from 'react-native';
import { Ionicons } from '@expo/vector-icons';

export interface EmptyStateProps {
  title: string;
  description?: string;
  icon?: keyof typeof Ionicons.glyphMap;
}

export function EmptyState({ title, description, icon = 'file-tray-outline' }: EmptyStateProps) {
  return (
    <View className="flex-1 items-center justify-center px-8 py-16">
      <View className="w-20 h-20 rounded-full bg-gray-100 items-center justify-center mb-4">
        <Ionicons name={icon} size={40} color="#9ca3af" />
      </View>

      <Text className="text-lg font-semibold text-gray-800 text-center mb-2">{title}</Text>

      {description ? (
        <Text className="text-sm text-gray-500 text-center leading-5">{description}</Text>
      ) : null}
    </View>
  );
}
