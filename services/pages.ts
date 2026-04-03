import type { AxiosResponse } from 'axios';
import { apiClient } from './api-client';
import type { PageItem, PageFormData, PageListResponse } from '../types/page';
import type { ListParams } from '../types/common';

export const pagesService = {
  getList: (params?: ListParams): Promise<AxiosResponse<PageListResponse>> =>
    apiClient.get<PageListResponse>('/pages', { params }),

  getById: (id: string): Promise<AxiosResponse<PageItem>> =>
    apiClient.get<PageItem>(`/pages/${id}`),

  create: (data: PageFormData): Promise<AxiosResponse<PageItem>> =>
    apiClient.post<PageItem>('/pages', data),

  update: (id: string, data: Partial<PageFormData>): Promise<AxiosResponse<PageItem>> =>
    apiClient.patch<PageItem>(`/pages/${id}`, data),

  remove: (id: string): Promise<AxiosResponse<void>> =>
    apiClient.delete<void>(`/pages/${id}`),
};
