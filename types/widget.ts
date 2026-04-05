import type { BaseApiResponse, PagedResponse } from './common';
import type { BannerSummary } from './banner';
import type { PostSummary } from './post';

export type WidgetType = 'BANNER' | 'POST';

export interface WidgetItem {
  id: number;
  name: string;
  description?: string;
  type: WidgetType;
  content?: string;
  orderIndex: number;
  status: boolean;
  template?: string;
  banners?: BannerSummary[];
  posts?: PostSummary[];
}

export interface WidgetFormData {
  name: string;
  description?: string;
  type: WidgetType;
  content?: string;
  orderIndex?: number;
  status: boolean;
  template?: string;
  bannerIds?: number[];
  postIds?: number[];
}

export interface WidgetSummary {
  id: number;
  name: string;
  type: WidgetType;
  status: boolean;
  orderIndex: number;
}

export type WidgetListResponse = BaseApiResponse<WidgetItem[]>;
export type WidgetPagedResponse = BaseApiResponse<PagedResponse<WidgetItem>>;
export type WidgetResponse = BaseApiResponse<WidgetItem>;
