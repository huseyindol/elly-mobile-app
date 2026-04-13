import React, { useEffect, useRef } from 'react';
import { TouchableOpacity, Animated, StyleSheet } from 'react-native';
import { useThemeColor } from '../../hooks/useThemeColor';

interface AnimatedFilterChipProps {
  label: string;
  isActive: boolean;
  onPress: () => void;
}

export function AnimatedFilterChip({ label, isActive, onPress }: AnimatedFilterChipProps) {
  const { colors, isDark } = useThemeColor();
  const scaleAnim = useRef(new Animated.Value(isActive ? 1 : 0)).current;

  useEffect(() => {
    Animated.spring(scaleAnim, {
      toValue: isActive ? 1 : 0,
      useNativeDriver: false,
      friction: 7,
      tension: 50,
    }).start();
  }, [isActive, scaleAnim]);

  const backgroundColor = scaleAnim.interpolate({
    inputRange: [0, 1],
    outputRange: [isDark ? colors.surface : '#F3F4F6', colors.primary[600]],
  });

  const textColor = scaleAnim.interpolate({
    inputRange: [0, 1],
    outputRange: [isDark ? '#9CA3AF' : '#4B5563', '#FFFFFF'],
  });

  return (
    <TouchableOpacity onPress={onPress} activeOpacity={0.8}>
      <Animated.View
        style={[
          styles.chip,
          {
            backgroundColor,
            borderColor: isDark ? colors.border : 'transparent',
            borderWidth: isDark ? 1 : 0,
            transform: [
              {
                scale: scaleAnim.interpolate({
                  inputRange: [0, 1],
                  outputRange: [0.95, 1.05],
                }),
              },
            ],
            shadowColor: colors.primary[600],
            shadowOffset: { width: 0, height: isActive ? 4 : 0 },
            shadowOpacity: isActive ? 0.3 : 0,
            shadowRadius: isActive ? 6 : 0,
            elevation: isActive ? 4 : 0,
          },
        ]}
      >
        <Animated.Text style={[styles.chipText, { color: textColor, fontWeight: '600' }]}>
          {label}
        </Animated.Text>
      </Animated.View>
    </TouchableOpacity>
  );
}

const styles = StyleSheet.create({
  chip: {
    paddingHorizontal: 20,
    paddingVertical: 10,
    borderRadius: 24,
  },
  chipText: {
    fontSize: 14,
  },
});
