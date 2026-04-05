import type { BaseApiResponse, PagedResponse } from './common';
import type { SeoInfo } from './seo';

export interface PageItem {
  id: number;
  title: string;
  description?: string;
  slug: string;
  status: boolean;
  template?: string;
  seoInfo?: SeoInfo;
  componentIds?: number[];
  components?: unknown[];
}

export interface PageFormData {
  title: string;
  description?: string;
  slug: string;
  status: boolean;
  template?: string;
  seoInfo?: Omit<SeoInfo, 'id'>;
  componentIds?: number[];
}

export type PageListResponse = BaseApiResponse<PageItem[]>;
export type PagePagedResponse = BaseApiResponse<PagedResponse<PageItem>>;
export type PageResponse = BaseApiResponse<PageItem>;
