import type { AxiosResponse } from 'axios';
import { apiClient } from './api-client';
import type { ComponentItem, ComponentFormData, ComponentListResponse } from '../types/component';
import type { ListParams } from '../types/common';

export const componentsService = {
  getList: (params?: ListParams): Promise<AxiosResponse<ComponentListResponse>> =>
    apiClient.get<ComponentListResponse>('/components', { params }),

  getById: (id: string): Promise<AxiosResponse<ComponentItem>> =>
    apiClient.get<ComponentItem>(`/components/${id}`),

  create: (data: ComponentFormData): Promise<AxiosResponse<ComponentItem>> =>
    apiClient.post<ComponentItem>('/components', data),

  update: (id: string, data: Partial<ComponentFormData>): Promise<AxiosResponse<ComponentItem>> =>
    apiClient.patch<ComponentItem>(`/components/${id}`, data),

  remove: (id: string): Promise<AxiosResponse<void>> =>
    apiClient.delete<void>(`/components/${id}`),
};
