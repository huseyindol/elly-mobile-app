import type { BaseApiResponse, PagedResponse } from './common';

export interface BasicInfo {
  id?: string;
  sectionKey: string;
  title: string;
  description?: string;
  isActive: boolean;
  sortOrder: number;
  createdAt?: string;
  updatedAt?: string;
}

export interface ContentItem<T = Record<string, unknown>> {
  id: string;
  basicInfo: BasicInfo;
  contentType: string;
  metadata: T;
  createdAt: string;
  updatedAt: string;
}

export interface ContentInput {
  basicInfoId?: string;
  basicInfo?: Omit<BasicInfo, 'id' | 'createdAt' | 'updatedAt'>;
  contentType: string;
  metadata: Record<string, unknown>;
}

export type ContentResponse = BaseApiResponse<ContentItem>;
export type ContentListResponse = BaseApiResponse<ContentItem[]>;
export type ContentPagedResponse = BaseApiResponse<PagedResponse<ContentItem>>;
