// Elly Mobile App — Section component
// Renders a titled section block with an optional right-aligned action button.

import React from 'react';
import { Text, TouchableOpacity, View } from 'react-native';

interface SectionAction {
  label: string;
  onPress: () => void;
}

export interface SectionProps {
  title: string;
  children: React.ReactNode;
  action?: SectionAction;
}

export function Section({ title, children, action }: SectionProps) {
  return (
    <View className="mb-6">
      {/* Header row */}
      <View className="flex-row items-center justify-between mb-3">
        <Text className="text-base font-semibold text-gray-800">{title}</Text>

        {action ? (
          <TouchableOpacity onPress={action.onPress} activeOpacity={0.7}>
            <Text className="text-sm font-medium text-blue-600">{action.label}</Text>
          </TouchableOpacity>
        ) : null}
      </View>

      {/* Content */}
      {children}
    </View>
  );
}
