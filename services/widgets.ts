import type { AxiosResponse } from 'axios';
import { apiClient } from './api-client';
import type { WidgetItem, WidgetFormData, WidgetListResponse } from '../types/widget';
import type { ListParams } from '../types/common';

export const widgetsService = {
  getList: (params?: ListParams): Promise<AxiosResponse<WidgetListResponse>> =>
    apiClient.get<WidgetListResponse>('/widgets', { params }),

  getById: (id: string): Promise<AxiosResponse<WidgetItem>> =>
    apiClient.get<WidgetItem>(`/widgets/${id}`),

  create: (data: WidgetFormData): Promise<AxiosResponse<WidgetItem>> =>
    apiClient.post<WidgetItem>('/widgets', data),

  update: (id: string, data: Partial<WidgetFormData>): Promise<AxiosResponse<WidgetItem>> =>
    apiClient.patch<WidgetItem>(`/widgets/${id}`, data),

  remove: (id: string): Promise<AxiosResponse<void>> =>
    apiClient.delete<void>(`/widgets/${id}`),
};
