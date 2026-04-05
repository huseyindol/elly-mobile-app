export interface SeoInfo {
  id?: string;
  title: string;
  description: string;
  keywords?: string;
  canonicalUrl?: string;
  noIndex?: boolean;
  noFollow?: boolean;
}
