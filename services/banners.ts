import type { AxiosResponse } from 'axios';
import { apiClient } from './api-client';
import type { BannerItem, BannerFormData, BannerListResponse } from '../types/banner';
import type { ListParams } from '../types/common';

export const bannersService = {
  getList: (params?: ListParams): Promise<AxiosResponse<BannerListResponse>> =>
    apiClient.get<BannerListResponse>('/banners', { params }),

  getById: (id: string): Promise<AxiosResponse<BannerItem>> =>
    apiClient.get<BannerItem>(`/banners/${id}`),

  create: (data: BannerFormData): Promise<AxiosResponse<BannerItem>> =>
    apiClient.post<BannerItem>('/banners', data),

  update: (id: string, data: Partial<BannerFormData>): Promise<AxiosResponse<BannerItem>> =>
    apiClient.patch<BannerItem>(`/banners/${id}`, data),

  remove: (id: string): Promise<AxiosResponse<void>> =>
    apiClient.delete<void>(`/banners/${id}`),
};
