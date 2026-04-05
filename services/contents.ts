import { apiClient } from './api-client';
import type { ContentResponse, ContentListResponse, ContentPagedResponse } from '../types/content';
import type { ContentInput } from '../types/content';
import type { ListParams } from '../types/common';

export const contentsService = {
  getBySection: (sectionKey: string) =>
    apiClient.get<ContentListResponse>(`/contents/section/${encodeURIComponent(sectionKey)}`),

  getById: (id: string) =>
    apiClient.get<ContentResponse>(`/contents/${id}`),

  getListPaged: (params?: ListParams) =>
    apiClient.get<ContentPagedResponse>('/contents/list/paged', { params }),

  create: (data: ContentInput) =>
    apiClient.post<ContentResponse>('/contents', data),

  update: (id: string, data: Partial<ContentInput>) =>
    apiClient.put<ContentResponse>(`/contents/${id}`, data),

  remove: (id: string) =>
    apiClient.delete<void>(`/contents/${id}`),
};
