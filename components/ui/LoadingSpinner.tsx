// Elly Mobile App — LoadingSpinner component
// Centered ActivityIndicator wrapper with configurable size and color.

import React, { useEffect, useRef } from 'react';
import { View, Animated, Easing, StyleSheet } from 'react-native';
import { useThemeColor } from '../../hooks/useThemeColor';

export interface LoadingSpinnerProps {
  size?: 'small' | 'large';
  color?: string;
}

export function LoadingSpinner({ size = 'large', color }: LoadingSpinnerProps) {
  const { colors } = useThemeColor();
  const spinValue = useRef(new Animated.Value(0)).current;

  useEffect(() => {
    Animated.loop(
      Animated.timing(spinValue, {
        toValue: 1,
        duration: 900,
        easing: Easing.bezier(0.4, 0, 0.2, 1), // smooth swift ease
        useNativeDriver: true,
      })
    ).start();
  }, [spinValue]);

  const spin = spinValue.interpolate({
    inputRange: [0, 1],
    outputRange: ['0deg', '360deg'],
  });

  const spinnerSize = size === 'large' ? 44 : 26;
  const borderWidth = size === 'large' ? 4 : 3;
  const spinnerColor = color || colors.primary[600];

  return (
    <View style={[styles.container, { backgroundColor: colors.background }]}>
      <Animated.View
        style={[
          styles.spinner,
          {
            width: spinnerSize,
            height: spinnerSize,
            borderRadius: spinnerSize / 2,
            borderWidth,
            borderColor: `${spinnerColor}22`, // Very light transparent track
            borderTopColor: spinnerColor,
            borderRightColor: spinnerColor,
            transform: [{ rotate: spin }],
            shadowColor: spinnerColor,
            shadowOffset: { width: 0, height: 0 },
            shadowOpacity: 0.4,
            shadowRadius: 8,
            elevation: 5,
          },
        ]}
      />
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
  },
  spinner: {
    justifyContent: 'center',
    alignItems: 'center',
  },
});
