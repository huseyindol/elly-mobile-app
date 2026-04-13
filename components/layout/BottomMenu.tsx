import React from 'react';
import { View, Text, TouchableOpacity, StyleSheet } from 'react-native';
import { useRouter, useSegments } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useThemeColor } from '../../hooks/useThemeColor';

export function BottomMenu() {
  const router = useRouter();
  const segments = useSegments();
  const insets = useSafeAreaInsets();
  const { colors } = useThemeColor();

  // Hide the menu on detail screens ([id]) or create screens (new)
  if (segments.includes('[id]' as string) || segments.includes('new' as string)) {
    return null;
  }

  // Determine current active tab
  const getIsActive = (routeName: string) => segments.includes(routeName as string);

  const menuItems = [
    { name: 'assets', label: 'Dosyalar', icon: 'folder-outline', activeIcon: 'folder' },
    { name: 'banners', label: 'Bannerlar', icon: 'images-outline', activeIcon: 'images' },
    { name: 'dashboard', label: '', icon: 'home', activeIcon: 'home', isCenter: true },
    { name: 'posts', label: 'Yazılar', icon: 'document-text-outline', activeIcon: 'document-text' },
    { name: 'components', label: 'Bileşenler', icon: 'cube-outline', activeIcon: 'cube' },
  ];

  return (
    <View style={[styles.container, { paddingBottom: Math.max(insets.bottom, 16) }]}>
      <View style={[styles.bar, { backgroundColor: colors.surface }]}>
        {menuItems.map((item, index) => {
          const isActive = getIsActive(item.name);

          if (item.isCenter) {
            return (
              <View key={item.name} style={styles.centerButtonContainer}>
                <TouchableOpacity
                  activeOpacity={0.8}
                  style={styles.centerButton}
                  onPress={() => router.push(`/(drawer)/${item.name}` as `/${string}`)}
                >
                  <Ionicons
                    name={
                      (isActive ? item.activeIcon : item.icon) as keyof typeof Ionicons.glyphMap
                    }
                    size={28}
                    color="#FFF"
                  />
                </TouchableOpacity>
              </View>
            );
          }

          return (
            <TouchableOpacity
              key={item.name}
              style={styles.tabButton}
              activeOpacity={0.6}
              onPress={() => router.push(`/(drawer)/${item.name}` as `/${string}`)}
            >
              <Ionicons
                name={(isActive ? item.activeIcon : item.icon) as keyof typeof Ionicons.glyphMap}
                size={24}
                color={isActive ? colors.primary[500] : colors.icon}
              />
              <Text
                style={[
                  styles.tabLabel,
                  { color: colors.textSubtle },
                  isActive && { color: colors.primary[500], fontWeight: '700' },
                ]}
              >
                {item.label}
              </Text>
            </TouchableOpacity>
          );
        })}
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    position: 'absolute',
    bottom: 0,
    left: 0,
    right: 0,
    alignItems: 'center',
    pointerEvents: 'box-none',
  },
  bar: {
    flexDirection: 'row',
    backgroundColor: '#FFFFFF',
    width: '94%',
    height: 70,
    borderRadius: 35,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 10 },
    shadowOpacity: 0.1,
    shadowRadius: 20,
    elevation: 10,
    alignItems: 'center',
    justifyContent: 'space-evenly',
    paddingHorizontal: 10,
  },
  tabButton: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    height: '100%',
  },
  tabLabel: {
    fontSize: 10,
    marginTop: 4,
    fontWeight: '500',
  },
  centerButtonContainer: {
    flex: 1.2,
    alignItems: 'center',
    justifyContent: 'center',
  },
  centerButton: {
    width: 64,
    height: 64,
    borderRadius: 32,
    backgroundColor: '#4F46E5',
    alignItems: 'center',
    justifyContent: 'center',
    marginBottom: 35, // Push it up above the bar
    shadowColor: '#4F46E5',
    shadowOffset: { width: 0, height: 8 },
    shadowOpacity: 0.4,
    shadowRadius: 10,
    elevation: 8,
  },
});
