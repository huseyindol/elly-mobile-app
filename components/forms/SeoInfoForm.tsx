// Elly Mobile App — SeoInfoSection component
// Collapsible container for SEO-related form fields.
// Usage: wrap <FormField> children for seoTitle, seoDescription, seoKeywords, noIndex, noFollow.

import { useState } from 'react';
import { View, Text, TouchableOpacity, StyleSheet } from 'react-native';
import { Ionicons } from '@expo/vector-icons';

interface SeoInfoSectionProps {
  children: React.ReactNode;
  defaultOpen?: boolean;
}

export function SeoInfoSection({ children, defaultOpen = false }: SeoInfoSectionProps) {
  const [open, setOpen] = useState(defaultOpen);

  return (
    <View style={styles.section}>
      <TouchableOpacity
        style={styles.header}
        onPress={() => setOpen(!open)}
        activeOpacity={0.7}
      >
        <View style={styles.headerLeft}>
          <Ionicons name="search-outline" size={18} color="#4F46E5" />
          <Text style={styles.title}>SEO Ayarları</Text>
        </View>
        <Ionicons
          name={open ? 'chevron-up' : 'chevron-down'}
          size={18}
          color="#9CA3AF"
        />
      </TouchableOpacity>
      {open && <View style={styles.content}>{children}</View>}
    </View>
  );
}

const styles = StyleSheet.create({
  section: {
    backgroundColor: '#fff',
    borderRadius: 12,
    marginBottom: 16,
    overflow: 'hidden',
    borderWidth: 1,
    borderColor: '#E5E7EB',
  },
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    padding: 16,
  },
  headerLeft: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 10,
  },
  title: {
    fontSize: 15,
    fontWeight: '600',
    color: '#111827',
  },
  content: {
    padding: 16,
    paddingTop: 0,
    gap: 12,
  },
});
