import { View, Text, TouchableOpacity, StyleSheet, Animated } from 'react-native';
import { useThemeColor } from '../../hooks/useThemeColor';
import { useEffect, useRef } from 'react';

interface ModernSwitchProps {
  value: boolean;
  onChange: (value: boolean) => void;
  label?: string;
  description?: string;
}

export function ModernSwitch({ value, onChange, label, description }: ModernSwitchProps) {
  const { colors, isDark } = useThemeColor();
  const slideAnim = useRef(new Animated.Value(value ? 1 : 0)).current;

  useEffect(() => {
    Animated.timing(slideAnim, {
      toValue: value ? 1 : 0,
      duration: 200,
      useNativeDriver: false,
    }).start();
  }, [value, slideAnim]);

  const backgroundColor = slideAnim.interpolate({
    inputRange: [0, 1],
    outputRange: [isDark ? '#374151' : '#E5E7EB', '#EF4444'], // Red because it's typically "No Index" = True -> Red Warning
  });

  const translateX = slideAnim.interpolate({
    inputRange: [0, 1],
    outputRange: [2, 22],
  });

  return (
    <View style={styles.container}>
      <View style={styles.textContainer}>
        {!!label && <Text style={[styles.label, { color: colors.text }]}>{label}</Text>}
        {!!description && (
          <Text style={[styles.description, { color: isDark ? '#9CA3AF' : '#6B7280' }]}>
            {description}
          </Text>
        )}
      </View>
      <TouchableOpacity activeOpacity={0.8} onPress={() => onChange(!value)}>
        <Animated.View style={[styles.track, { backgroundColor }]}>
          <Animated.View style={[styles.thumb, { transform: [{ translateX }] }]} />
        </Animated.View>
      </TouchableOpacity>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingVertical: 8,
  },
  textContainer: {
    flex: 1,
    paddingRight: 16,
  },
  label: {
    fontSize: 14,
    fontWeight: '600',
    marginBottom: 2,
  },
  description: {
    fontSize: 12,
  },
  track: {
    width: 44,
    height: 24,
    borderRadius: 12,
    justifyContent: 'center',
  },
  thumb: {
    width: 20,
    height: 20,
    borderRadius: 10,
    backgroundColor: '#FFFFFF',
    shadowColor: '#000',
    shadowOffset: {
      width: 0,
      height: 2,
    },
    shadowOpacity: 0.15,
    shadowRadius: 2,
    elevation: 2,
  },
});
