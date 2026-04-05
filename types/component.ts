import type { BaseApiResponse, PagedResponse } from './common';
import type { BannerSummary } from './banner';
import type { WidgetSummary } from './widget';

export type ComponentType = 'BANNER' | 'WIDGET' | 'FORM';

export interface ComponentItem {
  id: number;
  name: string;
  description?: string;
  type: ComponentType;
  content?: string;
  orderIndex: number;
  status: boolean;
  template?: string;
  pageIds?: number[];
  banners?: BannerSummary[];
  widgets?: WidgetSummary[];
  forms?: unknown[];
}

export interface ComponentFormData {
  name: string;
  description?: string;
  type: ComponentType;
  content?: string;
  orderIndex?: number;
  status: boolean;
  template?: string;
  pageIds?: number[];
  bannerIds?: number[];
  widgetIds?: number[];
  formIds?: number[];
}

export interface ComponentSummary {
  id: number;
  name: string;
  type: ComponentType;
  status: boolean;
  orderIndex: number;
}

export type ComponentListResponse = BaseApiResponse<ComponentItem[]>;
export type ComponentPagedResponse = BaseApiResponse<PagedResponse<ComponentItem>>;
export type ComponentResponse = BaseApiResponse<ComponentItem>;
