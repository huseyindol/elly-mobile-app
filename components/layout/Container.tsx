// Elly Mobile App — Container component
// Safe-area-aware full-screen container. Optionally wraps children in a
// ScrollView and applies consistent horizontal padding.

import React from 'react';
import { ScrollView, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';

export interface ContainerProps {
  children: React.ReactNode;
  scroll?: boolean;
  padding?: boolean;
}

export function Container({ children, scroll = false, padding = true }: ContainerProps) {
  const paddingClass = padding ? 'px-4' : '';

  if (scroll) {
    return (
      <SafeAreaView className="flex-1 bg-gray-50">
        <ScrollView
          className={`flex-1 ${paddingClass}`}
          contentContainerStyle={{ paddingBottom: 32 }}
          showsVerticalScrollIndicator={false}
          keyboardShouldPersistTaps="handled"
        >
          {children}
        </ScrollView>
      </SafeAreaView>
    );
  }

  return (
    <SafeAreaView className="flex-1 bg-gray-50">
      <View className={`flex-1 ${paddingClass}`}>
        {children}
      </View>
    </SafeAreaView>
  );
}
