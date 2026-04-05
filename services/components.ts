import type { AxiosResponse } from 'axios';
import { apiClient } from './api-client';
import type {
  ComponentFormData,
  ComponentListResponse,
  ComponentPagedResponse,
  ComponentResponse,
  ComponentSummary,
} from '../types/component';
import type { BaseApiResponse, ListParams } from '../types/common';

export const componentsService = {
  getList: (): Promise<AxiosResponse<ComponentListResponse>> =>
    apiClient.get<ComponentListResponse>('/components/list'),

  getListPaged: (params?: ListParams): Promise<AxiosResponse<ComponentPagedResponse>> =>
    apiClient.get<ComponentPagedResponse>('/components/list/paged', { params }),

  getSummary: (): Promise<AxiosResponse<BaseApiResponse<ComponentSummary[]>>> =>
    apiClient.get<BaseApiResponse<ComponentSummary[]>>('/components/list/summary'),

  getById: (id: number): Promise<AxiosResponse<ComponentResponse>> =>
    apiClient.get<ComponentResponse>(`/components/${id}`),

  create: (data: ComponentFormData): Promise<AxiosResponse<ComponentResponse>> =>
    apiClient.post<ComponentResponse>('/components', data),

  update: (
    id: number,
    data: Partial<ComponentFormData>,
  ): Promise<AxiosResponse<ComponentResponse>> =>
    apiClient.put<ComponentResponse>(`/components/${id}`, data),

  remove: (id: number): Promise<AxiosResponse<void>> =>
    apiClient.delete<void>(`/components/${id}`),
};
