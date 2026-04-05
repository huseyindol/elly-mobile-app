import type { BaseApiResponse, PagedResponse } from './common';
import type { SeoInfo } from './seo';

export interface PostItem {
  id: number;
  title: string;
  content?: string;
  slug: string;
  status: boolean;
  orderIndex: number;
  template?: string;
  seoInfo?: SeoInfo;
}

export interface PostFormData {
  title: string;
  content?: string;
  slug: string;
  status: boolean;
  orderIndex?: number;
  template?: string;
  seoInfo?: Omit<SeoInfo, 'id'>;
}

export interface PostSummary {
  id: number;
  title: string;
  slug: string;
  status: boolean;
  orderIndex: number;
}

export type PostListResponse = BaseApiResponse<PostItem[]>;
export type PostPagedResponse = BaseApiResponse<PagedResponse<PostItem>>;
export type PostResponse = BaseApiResponse<PostItem>;
