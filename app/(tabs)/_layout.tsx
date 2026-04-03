// Tab navigator layout — defines the five main admin sections.
// Architectural decision: each tab maps 1:1 to an admin panel section.
// activeTintColor uses the Indigo-600 brand color (#4F46E5) per design spec.

import React from 'react';
import { Tabs } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';

type IoniconName = React.ComponentProps<typeof Ionicons>['name'];

interface TabConfig {
  name: string;
  title: string;
  activeIcon: IoniconName;
  inactiveIcon: IoniconName;
}

const TAB_CONFIG: TabConfig[] = [
  {
    name: 'dashboard/index',
    title: 'Dashboard',
    activeIcon: 'grid',
    inactiveIcon: 'grid-outline',
  },
  {
    name: 'pages/index',
    title: 'Pages',
    activeIcon: 'document-text',
    inactiveIcon: 'document-text-outline',
  },
  {
    name: 'posts/index',
    title: 'Posts',
    activeIcon: 'newspaper',
    inactiveIcon: 'newspaper-outline',
  },
  {
    name: 'banners/index',
    title: 'Banners',
    activeIcon: 'image',
    inactiveIcon: 'image-outline',
  },
  {
    name: 'components/index',
    title: 'Components',
    activeIcon: 'cube',
    inactiveIcon: 'cube-outline',
  },
];

const ACTIVE_TINT = '#4F46E5';
const INACTIVE_TINT = '#6B7280';

export default function TabsLayout() {
  return (
    <Tabs
      screenOptions={{
        tabBarActiveTintColor: ACTIVE_TINT,
        tabBarInactiveTintColor: INACTIVE_TINT,
        tabBarStyle: {
          backgroundColor: '#FFFFFF',
          borderTopColor: '#E5E7EB',
          borderTopWidth: 1,
        },
        tabBarLabelStyle: {
          fontSize: 11,
          fontWeight: '500',
        },
        headerStyle: {
          backgroundColor: '#FFFFFF',
        },
        headerTintColor: '#111827',
        headerTitleStyle: {
          fontWeight: '600',
          fontSize: 18,
        },
        headerShadowVisible: false,
      }}
    >
      {TAB_CONFIG.map((tab) => (
        <Tabs.Screen
          key={tab.name}
          name={tab.name}
          options={{
            title: tab.title,
            tabBarIcon: ({ focused, color, size }: { focused: boolean; color: string; size: number }) => (
              <Ionicons
                name={focused ? tab.activeIcon : tab.inactiveIcon}
                color={color}
                size={size}
              />
            ),
          }}
        />
      ))}

      {/* Hidden detail screens — accessible via navigation, not tabs */}
      <Tabs.Screen name="pages/[id]" options={{ href: null, title: 'Page Detail' }} />
      <Tabs.Screen name="posts/[id]" options={{ href: null, title: 'Post Detail' }} />
      <Tabs.Screen name="banners/[id]" options={{ href: null, title: 'Banner Detail' }} />
      <Tabs.Screen name="components/[id]" options={{ href: null, title: 'Component Detail' }} />
    </Tabs>
  );
}
