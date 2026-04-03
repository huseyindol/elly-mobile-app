// Elly Mobile App — Input component
// Labelled text input with inline error display. Integrates with react-hook-form
// via the FormField wrapper but can also be used standalone.

import React, { useState } from 'react';
import { Text, TextInput, View } from 'react-native';

export interface InputProps {
  label?: string;
  placeholder?: string;
  value: string;
  onChangeText: (text: string) => void;
  error?: string;
  secureTextEntry?: boolean;
  multiline?: boolean;
  numberOfLines?: number;
}

export function Input({
  label,
  placeholder,
  value,
  onChangeText,
  error,
  secureTextEntry = false,
  multiline = false,
  numberOfLines = 1,
}: InputProps) {
  const [focused, setFocused] = useState(false);

  const borderClass = error
    ? 'border-red-500'
    : focused
    ? 'border-blue-500'
    : 'border-gray-300';

  const inputHeight = multiline ? numberOfLines * 24 + 16 : undefined;

  return (
    <View className="w-full mb-4">
      {label ? (
        <Text className="text-sm font-medium text-gray-700 mb-1">{label}</Text>
      ) : null}

      <TextInput
        className={`w-full px-3 py-2.5 bg-white rounded-lg border text-base text-gray-900 ${borderClass}`}
        style={inputHeight ? { height: inputHeight, textAlignVertical: 'top' } : undefined}
        placeholder={placeholder}
        placeholderTextColor="#9ca3af"
        value={value}
        onChangeText={onChangeText}
        secureTextEntry={secureTextEntry}
        multiline={multiline}
        numberOfLines={multiline ? numberOfLines : undefined}
        onFocus={() => setFocused(true)}
        onBlur={() => setFocused(false)}
        autoCapitalize="none"
        autoCorrect={false}
      />

      {error ? (
        <Text className="text-xs text-red-500 mt-1">{error}</Text>
      ) : null}
    </View>
  );
}
