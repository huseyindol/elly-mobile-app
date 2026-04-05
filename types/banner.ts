import type { BaseApiResponse, PagedResponse } from './common';

export type BannerTarget = '_blank' | '_self';

export interface BannerImages {
  desktop?: string;
  tablet?: string;
  mobile?: string;
}

export interface BannerItem {
  id: number;
  title: string;
  altText?: string;
  images: BannerImages;
  link?: string;
  target: BannerTarget;
  type?: string;
  orderIndex: number;
  status: boolean;
  subFolder?: string;
}

export interface BannerFormData {
  title: string;
  altText?: string;
  link?: string;
  target: BannerTarget;
  type?: string;
  orderIndex: number;
  status: boolean;
  subFolder?: string;
  images?: BannerImages;
}

export interface BannerImageFiles {
  desktop?: { uri: string; type: string; name: string };
  tablet?: { uri: string; type: string; name: string };
  mobile?: { uri: string; type: string; name: string };
}

export interface BannerSummary {
  id: number;
  title: string;
  status: boolean;
  orderIndex: number;
  subFolder?: string;
}

export type BannerListResponse = BaseApiResponse<BannerItem[]>;
export type BannerPagedResponse = BaseApiResponse<PagedResponse<BannerItem>>;
export type BannerResponse = BaseApiResponse<BannerItem>;
