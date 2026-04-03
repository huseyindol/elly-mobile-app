import type { PaginatedResponse } from './common';

export type PageStatus = 'draft' | 'published' | 'archived';

export interface PageItem {
  id: string;
  title: string;
  slug: string;
  status: PageStatus;
  createdAt: string;
  updatedAt: string;
}

export interface PageFormData {
  title: string;
  slug: string;
  status: PageStatus;
  content?: string;
}

export type PageListResponse = PaginatedResponse<PageItem>;
