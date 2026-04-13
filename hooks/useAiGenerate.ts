import { useState } from 'react';
import { Alert } from 'react-native';
import { AiService } from '../services/ai';
import type { GeneratedSeoFields } from '../services/ai';

export function useAiGenerate() {
  const [slugLoading, setSlugLoading] = useState(false);
  const [descriptionLoading, setDescriptionLoading] = useState(false);
  const [seoLoading, setSeoLoading] = useState(false);
  const [altTextLoading, setAltTextLoading] = useState(false);
  const [articleLoading, setArticleLoading] = useState(false);

  const safeCall = async <T>(
    apiCall: () => Promise<T>,
    setLoading: (state: boolean) => void,
    successCb: (data: T) => void,
    errorMsg: string
  ) => {
    try {
      setLoading(true);
      const data = await apiCall();
      successCb(data);
    } catch (error: unknown) {
      const message = error instanceof Error ? error.message : errorMsg;
      Alert.alert('AI Hatası', message);
    } finally {
      setLoading(false);
    }
  };

  const handleAiSlug = async (title: string, onGenerate: (slug: string) => void) => {
    if (!title) return;
    await safeCall(
      () => AiService.generateSlug(title),
      setSlugLoading,
      onGenerate,
      'Slug oluşturulamadı'
    );
  };

  const handleAiDescription = async (
    name: string,
    context: string,
    onGenerate: (desc: string) => void
  ) => {
    if (!name) return;
    await safeCall(
      () => AiService.generateDescription(name, context),
      setDescriptionLoading,
      onGenerate,
      'Açıklama oluşturulamadı'
    );
  };

  const handleAiSeo = async (title: string, onGenerate: (seo: GeneratedSeoFields) => void) => {
    if (!title) return;
    await safeCall(
      () => AiService.generateSeoFields(title),
      setSeoLoading,
      onGenerate,
      'SEO alanları oluşturulamadı'
    );
  };

  const handleAiAltText = async (title: string, onGenerate: (alt: string) => void) => {
    if (!title) return;
    await safeCall(
      () => AiService.generateAltText(title),
      setAltTextLoading,
      onGenerate,
      'Alt metin oluşturulamadı'
    );
  };

  const handleAiArticle = async (
    topic: string,
    keywords: string,
    onGenerate: (html: string) => void
  ) => {
    if (!topic) return;
    await safeCall(
      () => AiService.generateArticle(topic, keywords),
      setArticleLoading,
      onGenerate,
      'Makale oluşturulamadı'
    );
  };

  return {
    slugLoading,
    descriptionLoading,
    seoLoading,
    altTextLoading,
    articleLoading,
    handleAiSlug,
    handleAiDescription,
    handleAiSeo,
    handleAiAltText,
    handleAiArticle,
  };
}
