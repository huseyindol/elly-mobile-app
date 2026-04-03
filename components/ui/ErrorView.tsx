// Elly Mobile App — ErrorView component
// Displays an error message with an optional retry action.

import React from 'react';
import { Text, View } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { Button } from './Button';

export interface ErrorViewProps {
  message: string;
  onRetry?: () => void;
}

export function ErrorView({ message, onRetry }: ErrorViewProps) {
  return (
    <View className="flex-1 items-center justify-center px-8 py-16">
      <View className="w-20 h-20 rounded-full bg-red-100 items-center justify-center mb-4">
        <Ionicons name="alert-circle-outline" size={40} color="#ef4444" />
      </View>

      <Text className="text-lg font-semibold text-gray-800 text-center mb-2">
        Something went wrong
      </Text>

      <Text className="text-sm text-gray-500 text-center leading-5 mb-6">
        {message}
      </Text>

      {onRetry ? (
        <Button label="Try again" onPress={onRetry} variant="primary" icon="refresh-outline" />
      ) : null}
    </View>
  );
}
