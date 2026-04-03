import type { PaginatedResponse } from './common';

export interface BannerItem {
  id: string;
  title: string;
  imageUrl: string;
  isActive: boolean;
  startDate: string;
  endDate: string;
  createdAt: string;
  updatedAt: string;
}

export interface BannerFormData {
  title: string;
  imageUrl: string;
  isActive: boolean;
  startDate: string;
  endDate: string;
}

export type BannerListResponse = PaginatedResponse<BannerItem>;
