import type { AxiosResponse } from 'axios';
import { apiClient } from './api-client';
import type {
  BannerFormData,
  BannerImageFiles,
  BannerListResponse,
  BannerPagedResponse,
  BannerResponse,
} from '../types/banner';
import type { BaseApiResponse, ListParams } from '../types/common';

const buildBannerFormData = (
  data: BannerFormData | Partial<BannerFormData>,
  imageFiles?: BannerImageFiles,
): FormData => {
  const formData = new FormData();
  formData.append('data', JSON.stringify(data));
  if (imageFiles?.desktop) {
    formData.append('desktop', imageFiles.desktop as unknown as Blob);
  }
  if (imageFiles?.tablet) {
    formData.append('tablet', imageFiles.tablet as unknown as Blob);
  }
  if (imageFiles?.mobile) {
    formData.append('mobile', imageFiles.mobile as unknown as Blob);
  }
  return formData;
};

export const bannersService = {
  getList: (): Promise<AxiosResponse<BannerListResponse>> =>
    apiClient.get<BannerListResponse>('/banners/list'),

  getListPaged: (params?: ListParams): Promise<AxiosResponse<BannerPagedResponse>> =>
    apiClient.get<BannerPagedResponse>('/banners/list/paged', { params }),

  getById: (id: number): Promise<AxiosResponse<BannerResponse>> =>
    apiClient.get<BannerResponse>(`/banners/${id}`),

  getSubFolders: (): Promise<AxiosResponse<BaseApiResponse<string[]>>> =>
    apiClient.get<BaseApiResponse<string[]>>('/banners/sub-folders'),

  getBySubFolder: (subFolder: string): Promise<AxiosResponse<BannerListResponse>> =>
    apiClient.get<BannerListResponse>(`/banners/list/${encodeURIComponent(subFolder)}`),

  getSummary: (): Promise<AxiosResponse<BannerListResponse>> =>
    apiClient.get<BannerListResponse>('/banners/list/summary'),

  create: (
    data: BannerFormData,
    imageFiles?: BannerImageFiles,
  ): Promise<AxiosResponse<BannerResponse>> =>
    apiClient.post<BannerResponse>('/banners', buildBannerFormData(data, imageFiles), {
      headers: { 'Content-Type': 'multipart/form-data' },
    }),

  update: (
    id: number,
    data: Partial<BannerFormData>,
    imageFiles?: BannerImageFiles,
  ): Promise<AxiosResponse<BannerResponse>> =>
    apiClient.put<BannerResponse>(`/banners/${id}`, buildBannerFormData(data, imageFiles), {
      headers: { 'Content-Type': 'multipart/form-data' },
    }),

  remove: (id: number): Promise<AxiosResponse<void>> =>
    apiClient.delete<void>(`/banners/${id}`),
};
