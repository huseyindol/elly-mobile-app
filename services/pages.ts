import type { AxiosResponse } from 'axios';
import { apiClient } from './api-client';
import type {
  PageFormData,
  PageListResponse,
  PagePagedResponse,
  PageResponse,
} from '../types/page';
import type { ListParams } from '../types/common';

export const pagesService = {
  getList: (): Promise<AxiosResponse<PageListResponse>> =>
    apiClient.get<PageListResponse>('/pages/list'),

  getListSummary: (): Promise<AxiosResponse<PageListResponse>> =>
    apiClient.get<PageListResponse>('/pages/list/summary'),

  getListPaged: (params?: ListParams): Promise<AxiosResponse<PagePagedResponse>> =>
    apiClient.get<PagePagedResponse>('/pages/list/paged', { params }),

  getBySlug: (slug: string): Promise<AxiosResponse<PageResponse>> =>
    apiClient.get<PageResponse>(`/pages/${slug}`),

  create: (data: PageFormData): Promise<AxiosResponse<PageResponse>> =>
    apiClient.post<PageResponse>('/pages', data),

  update: (id: number, data: Partial<PageFormData>): Promise<AxiosResponse<PageResponse>> =>
    apiClient.put<PageResponse>(`/pages/${id}`, data),

  remove: (id: number): Promise<AxiosResponse<void>> => apiClient.delete<void>(`/pages/${id}`),
};
