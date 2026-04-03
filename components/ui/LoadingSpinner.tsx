// Elly Mobile App — LoadingSpinner component
// Centered ActivityIndicator wrapper with configurable size and color.

import React from 'react';
import { ActivityIndicator, View } from 'react-native';

export interface LoadingSpinnerProps {
  size?: 'small' | 'large';
  color?: string;
}

export function LoadingSpinner({ size = 'large', color = '#3b82f6' }: LoadingSpinnerProps) {
  return (
    <View className="flex-1 items-center justify-center p-8">
      <ActivityIndicator size={size} color={color} />
    </View>
  );
}
