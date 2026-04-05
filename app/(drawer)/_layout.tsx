// Architecture: Drawer navigator wrapping all admin sections
// Uses @react-navigation/drawer via expo-router/drawer
import { GestureHandlerRootView } from 'react-native-gesture-handler';
import { Drawer } from 'expo-router/drawer';
import { DrawerContent } from '../../components/layout/DrawerContent';

export default function DrawerLayout() {
  return (
    <GestureHandlerRootView style={{ flex: 1 }}>
      <Drawer
        drawerContent={(props) => <DrawerContent {...props} />}
        screenOptions={{
          headerStyle: { backgroundColor: '#fff' },
          headerTintColor: '#111827',
          headerTitleStyle: { fontWeight: '600', fontSize: 18 },
          drawerStyle: { backgroundColor: '#fff', width: 280 },
        }}
      >
        <Drawer.Screen name="dashboard/index" options={{ title: 'Dashboard', drawerLabel: 'Dashboard' }} />
        <Drawer.Screen name="pages/index" options={{ title: 'Sayfalar', drawerLabel: 'Sayfalar' }} />
        <Drawer.Screen name="pages/[id]" options={{ title: 'Sayfa Detay', drawerItemStyle: { display: 'none' } }} />
        <Drawer.Screen name="pages/new" options={{ title: 'Yeni Sayfa', drawerItemStyle: { display: 'none' } }} />
        <Drawer.Screen name="posts/index" options={{ title: 'Yazılar', drawerLabel: 'Yazılar' }} />
        <Drawer.Screen name="posts/[id]" options={{ title: 'Yazı Detay', drawerItemStyle: { display: 'none' } }} />
        <Drawer.Screen name="posts/new" options={{ title: 'Yeni Yazı', drawerItemStyle: { display: 'none' } }} />
        <Drawer.Screen name="banners/index" options={{ title: 'Bannerlar', drawerLabel: 'Bannerlar' }} />
        <Drawer.Screen name="banners/[id]" options={{ title: 'Banner Detay', drawerItemStyle: { display: 'none' } }} />
        <Drawer.Screen name="banners/new" options={{ title: 'Yeni Banner', drawerItemStyle: { display: 'none' } }} />
        <Drawer.Screen name="components/index" options={{ title: 'Bileşenler', drawerLabel: 'Bileşenler' }} />
        <Drawer.Screen name="components/[id]" options={{ title: 'Bileşen Detay', drawerItemStyle: { display: 'none' } }} />
        <Drawer.Screen name="components/new" options={{ title: 'Yeni Bileşen', drawerItemStyle: { display: 'none' } }} />
        <Drawer.Screen name="widgets/index" options={{ title: "Widget'lar", drawerLabel: "Widget'lar" }} />
        <Drawer.Screen name="widgets/[id]" options={{ title: 'Widget Detay', drawerItemStyle: { display: 'none' } }} />
        <Drawer.Screen name="widgets/new" options={{ title: 'Yeni Widget', drawerItemStyle: { display: 'none' } }} />
        <Drawer.Screen name="assets/index" options={{ title: 'Dosyalar', drawerLabel: 'Dosyalar' }} />
        <Drawer.Screen name="assets/[id]" options={{ title: 'Dosya Detay', drawerItemStyle: { display: 'none' } }} />
        <Drawer.Screen name="forms/index" options={{ title: 'Formlar', drawerLabel: 'Formlar' }} />
        <Drawer.Screen name="forms/[id]" options={{ title: 'Form Detay', drawerItemStyle: { display: 'none' } }} />
        <Drawer.Screen name="forms/new" options={{ title: 'Yeni Form', drawerItemStyle: { display: 'none' } }} />
        <Drawer.Screen name="contents/index" options={{ title: 'İçerikler', drawerLabel: 'İçerikler' }} />
        <Drawer.Screen name="contents/[id]" options={{ title: 'İçerik Detay', drawerItemStyle: { display: 'none' } }} />
        <Drawer.Screen name="contents/new" options={{ title: 'Yeni İçerik', drawerItemStyle: { display: 'none' } }} />
        <Drawer.Screen name="settings/index" options={{ title: 'Ayarlar', drawerLabel: 'Ayarlar' }} />
      </Drawer>
    </GestureHandlerRootView>
  );
}
