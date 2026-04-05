import type { AxiosResponse } from 'axios';
import { apiClient } from './api-client';
import type {
  WidgetFormData,
  WidgetListResponse,
  WidgetPagedResponse,
  WidgetResponse,
  WidgetSummary,
} from '../types/widget';
import type { BaseApiResponse, ListParams } from '../types/common';

export const widgetsService = {
  getList: (): Promise<AxiosResponse<WidgetListResponse>> =>
    apiClient.get<WidgetListResponse>('/widgets/list'),

  getListPaged: (params?: ListParams): Promise<AxiosResponse<WidgetPagedResponse>> =>
    apiClient.get<WidgetPagedResponse>('/widgets/list/paged', { params }),

  getSummary: (): Promise<AxiosResponse<BaseApiResponse<WidgetSummary[]>>> =>
    apiClient.get<BaseApiResponse<WidgetSummary[]>>('/widgets/list/summary'),

  getById: (id: number): Promise<AxiosResponse<WidgetResponse>> =>
    apiClient.get<WidgetResponse>(`/widgets/${id}`),

  create: (data: WidgetFormData): Promise<AxiosResponse<WidgetResponse>> =>
    apiClient.post<WidgetResponse>('/widgets', data),

  update: (id: number, data: Partial<WidgetFormData>): Promise<AxiosResponse<WidgetResponse>> =>
    apiClient.put<WidgetResponse>(`/widgets/${id}`, data),

  remove: (id: number): Promise<AxiosResponse<void>> =>
    apiClient.delete<void>(`/widgets/${id}`),
};
