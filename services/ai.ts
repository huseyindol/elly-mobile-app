import { ENV } from '../constants/env';

const GEMINI_URL =
  'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent';

export interface GeneratedSeoFields {
  seoTitle: string;
  seoDescription: string;
  seoKeywords: string;
}

export const AiService = {
  async generateContent(prompt: string): Promise<string> {
    if (!ENV.API_KEY) {
      throw new Error('Gemini API anahtarı (EXPO_PUBLIC_API_KEY) tanımlı değil.');
    }

    try {
      const response = await fetch(`${GEMINI_URL}?key=${ENV.API_KEY}`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          contents: [{ parts: [{ text: prompt }] }],
        }),
      });

      if (!response.ok) {
        const errorData = await response.json().catch(() => ({}));
        throw new Error(errorData?.error?.message || `API hatası: ${response.status}`);
      }

      const data = await response.json();
      return data.candidates?.[0]?.content?.parts?.[0]?.text || '';
    } catch (error: unknown) {
      const message = error instanceof Error ? error.message : 'AI tarafında bir hata oluştu.';
      throw new Error(message);
    }
  },

  async generateSlug(title: string): Promise<string> {
    const prompt = `Aşağıdaki Türkçe başlıktan SEO dostu bir URL slug'ı oluştur.
Kurallar:
- Sadece küçük harf, rakam ve tire (-) kullan
- Türkçe karakterleri dönüştür (ş→s, ğ→g, ü→u, ö→o, ı→i, ç→c)
- Boşlukları tire ile değiştir
- Ardışık tireleri tekleştir
- Maksimum 80 karakter
- Sadece slug'ı döndür, başka hiçbir şey yazma

Başlık: ${title}`;

    const text = await this.generateContent(prompt);
    return text
      .trim()
      .toLowerCase()
      .replace(/[^a-z0-9-]/g, '')
      .replace(/-+/g, '-')
      .replace(/^-|-$/g, '');
  },

  async generateDescription(name: string, context?: string): Promise<string> {
    const prompt = `Aşağıdaki ${context ?? 'içerik'} adı için kısa ve açıklayıcı bir Türkçe açıklama yaz.
Ad: "${name}"

Kurallar:
- Maksimum 2 cümle
- Türkçe yaz
- Sadece açıklamayı döndür, başka hiçbir şey yazma`;

    const text = await this.generateContent(prompt);
    return text.trim();
  },

  async generateSeoFields(title: string): Promise<GeneratedSeoFields> {
    const prompt = `Aşağıdaki başlık için SEO meta verilerini Türkçe olarak oluştur.
Başlık: "${title}"

Tam olarak şu JSON formatında yanıt ver (başka hiçbir şey yazma):
{
  "seoTitle": "max 60 karakter SEO başlığı",
  "seoDescription": "max 155 karakter meta açıklaması, kullanıcıyı tıklamaya teşvik edecek",
  "seoKeywords": "anahtar1, anahtar2, anahtar3, anahtar4, anahtar5"
}`;

    const text = await this.generateContent(prompt);
    const raw = text
      .trim()
      .replace(/^```json\s*/i, '')
      .replace(/^```\s*/i, '')
      .replace(/\s*```$/i, '')
      .trim();

    return JSON.parse(raw) as GeneratedSeoFields;
  },

  async generateAltText(title: string): Promise<string> {
    const prompt = `Aşağıdaki başlık için bir banner görselinin SEO dostu alt metnini yaz.
Başlık: "${title}"

Kurallar:
- Maksimum 10 kelime
- Görseli kısaca açıkla, anahtar kelime içersin
- Türkçe yaz
- Sadece alt metni döndür, başka hiçbir şey yazma`;

    const text = await this.generateContent(prompt);
    return text.trim();
  },

  async generateArticle(topic: string, keywords?: string): Promise<string> {
    const targetKeywords = keywords ? keywords : '';
    const prompt = `Sen uzman bir içerik yazarısın. Aşağıdaki konu hakkında SEO uyumlu, detaylı ve bilgi verici bir makale yaz.
Konu: "${topic}"
${targetKeywords ? `Anahtar Kelimeler: "${targetKeywords}"` : ''}

Kurallar:
- Yazıyı HTML formatında ver (sadece içerik, <html> veya <body> etiketleri kullanma).
- Sadece HTML içeriğini döndür (başında/sonunda markdown kod blokları \`\`\`html vs. olmasın).
- H1 başlığı KULLANMA.
- Makaleyi H2 ve H3 başlıklarla yapılandır (<h2>, <h3>).
- Paragraflar için <p>, listeler için <ul> <li> kullan.
- Vurgulamak için <strong> etiketini kullan.
- Dil Türkçe ve üslup profesyonel fakat okuması kolay olsun.`;

    let text = await this.generateContent(prompt);

    // Remove markdown code blocks if any
    text = text
      .replace(/^```html\s*/i, '')
      .replace(/^```\s*/i, '')
      .replace(/\s*```$/i, '')
      .trim();
    return text;
  },
};
