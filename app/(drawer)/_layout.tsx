// Architecture: Drawer navigator wrapping all admin sections
// Uses @react-navigation/drawer via expo-router/drawer
import { GestureHandlerRootView } from 'react-native-gesture-handler';
import { Drawer } from 'expo-router/drawer';
import { DrawerContent } from '../../components/layout/DrawerContent';
import { BottomMenu } from '../../components/layout/BottomMenu';
import { useThemeColor } from '../../hooks/useThemeColor';

export default function DrawerLayout() {
  const { colors } = useThemeColor();

  return (
    <GestureHandlerRootView style={{ flex: 1, backgroundColor: colors.background }}>
      <Drawer
        drawerContent={(props) => <DrawerContent {...props} />}
        screenOptions={{
          headerStyle: { backgroundColor: colors.surface },
          headerTintColor: colors.text,
          headerTitleStyle: { fontWeight: '600', fontSize: 18 },
          drawerStyle: { backgroundColor: colors.surface, width: 280 },
        }}
      >
        <Drawer.Screen
          name="dashboard/index"
          options={{ title: 'Elly Panel', drawerLabel: 'Elly Panel' }}
        />
        <Drawer.Screen name="pages" options={{ title: 'Sayfalar', drawerLabel: 'Sayfalar' }} />
        <Drawer.Screen name="posts" options={{ title: 'Yazılar', drawerLabel: 'Yazılar' }} />
        <Drawer.Screen name="banners" options={{ title: 'Bannerlar', drawerLabel: 'Bannerlar' }} />
        <Drawer.Screen
          name="components"
          options={{ title: 'Bileşenler', drawerLabel: 'Bileşenler' }}
        />
        <Drawer.Screen
          name="widgets"
          options={{ title: "Widget'lar", drawerLabel: "Widget'lar" }}
        />
        <Drawer.Screen name="assets" options={{ title: 'Dosyalar', drawerLabel: 'Dosyalar' }} />
        <Drawer.Screen name="forms" options={{ title: 'Formlar', drawerLabel: 'Formlar' }} />
        <Drawer.Screen name="contents" options={{ title: 'İçerikler', drawerLabel: 'İçerikler' }} />
        <Drawer.Screen
          name="settings/index"
          options={{ title: 'Ayarlar', drawerLabel: 'Ayarlar' }}
        />
      </Drawer>
      <BottomMenu />
    </GestureHandlerRootView>
  );
}
