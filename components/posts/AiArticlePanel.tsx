import React, { useState } from 'react';
import {
  View,
  Text,
  TextInput,
  TouchableOpacity,
  ActivityIndicator,
  StyleSheet,
} from 'react-native';
import { useAiGenerate } from '../../hooks/useAiGenerate';

interface AiArticlePanelProps {
  onGenerated: (html: string) => void;
}

export function AiArticlePanel({ onGenerated }: AiArticlePanelProps) {
  const [topic, setTopic] = useState('');
  const [keywords, setKeywords] = useState('');

  const { articleLoading, handleAiArticle } = useAiGenerate();

  const handleGenerate = () => {
    handleAiArticle(topic, keywords, (html) => {
      onGenerated(html);
    });
  };

  return (
    <View style={styles.container}>
      <View style={styles.header}>
        <Text style={styles.icon}>✨</Text>
        <Text style={styles.title}>AI Makale Oluşturucu</Text>
        <Text style={styles.badge}>Gemini</Text>
      </View>

      <View style={styles.fieldGroup}>
        <Text style={styles.label}>Makale Konusu *</Text>
        <TextInput
          style={styles.input}
          value={topic}
          onChangeText={setTopic}
          placeholder="Örn: React Server Components nasıl çalışır?"
          editable={!articleLoading}
        />
      </View>

      <View style={styles.fieldGroup}>
        <Text style={styles.label}>Yardımcı Anahtar Kelimeler</Text>
        <TextInput
          style={styles.input}
          value={keywords}
          onChangeText={setKeywords}
          placeholder="Örn: performans, SSR, hydration"
          editable={!articleLoading}
        />
      </View>

      <TouchableOpacity
        style={[styles.button, (!topic.trim() || articleLoading) && styles.buttonDisabled]}
        onPress={handleGenerate}
        disabled={!topic.trim() || articleLoading}
        activeOpacity={0.8}
      >
        {articleLoading ? (
          <>
            <ActivityIndicator size="small" color="#FFF" style={{ marginRight: 8 }} />
            <Text style={styles.buttonText}>Makale Oluşturuluyor...</Text>
          </>
        ) : (
          <Text style={styles.buttonText}>✨ Makale Oluştur</Text>
        )}
      </TouchableOpacity>

      {articleLoading && (
        <Text style={styles.hintText}>
          Article Agent konu planlıyor → Makale taslağı hazırlanıyor
        </Text>
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    backgroundColor: '#FAF5FF',
    borderWidth: 1,
    borderColor: '#E9D5FF',
    borderRadius: 12,
    padding: 16,
    marginBottom: 16,
  },
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    marginBottom: 16,
  },
  icon: {
    fontSize: 16,
    marginRight: 8,
  },
  title: {
    fontSize: 14,
    fontWeight: '600',
    color: '#6B21A8',
    flex: 1,
  },
  badge: {
    fontSize: 10,
    fontWeight: '600',
    color: '#7E22CE',
    backgroundColor: '#F3E8FF',
    paddingHorizontal: 8,
    paddingVertical: 2,
    borderRadius: 12,
    overflow: 'hidden',
  },
  fieldGroup: {
    marginBottom: 12,
  },
  label: {
    fontSize: 12,
    fontWeight: '500',
    color: '#6B7280',
    marginBottom: 6,
  },
  input: {
    backgroundColor: '#FFF',
    borderWidth: 1,
    borderColor: '#E5E7EB',
    borderRadius: 8,
    paddingHorizontal: 12,
    paddingVertical: 10,
    fontSize: 14,
    color: '#111827',
  },
  button: {
    flexDirection: 'row',
    backgroundColor: '#7E22CE',
    paddingVertical: 12,
    borderRadius: 8,
    alignItems: 'center',
    justifyContent: 'center',
    marginTop: 8,
  },
  buttonDisabled: {
    backgroundColor: '#D8B4FE',
  },
  buttonText: {
    color: '#FFF',
    fontSize: 14,
    fontWeight: '600',
  },
  hintText: {
    marginTop: 12,
    textAlign: 'center',
    fontSize: 11,
    color: '#6B7280',
  },
});
