import type { AxiosResponse } from 'axios';
import { apiClient } from './api-client';
import type {
  PostFormData,
  PostListResponse,
  PostPagedResponse,
  PostResponse,
} from '../types/post';
import type { ListParams } from '../types/common';

export const postsService = {
  getList: (): Promise<AxiosResponse<PostListResponse>> =>
    apiClient.get<PostListResponse>('/posts/list'),

  getListSummary: (): Promise<AxiosResponse<PostListResponse>> =>
    apiClient.get<PostListResponse>('/posts/list/summary'),

  getListPaged: (params?: ListParams): Promise<AxiosResponse<PostPagedResponse>> =>
    apiClient.get<PostPagedResponse>('/posts/list/paged', { params }),

  getById: (id: number): Promise<AxiosResponse<PostResponse>> =>
    apiClient.get<PostResponse>(`/posts/${id}`),

  create: (data: PostFormData): Promise<AxiosResponse<PostResponse>> =>
    apiClient.post<PostResponse>('/posts', data),

  update: (id: number, data: Partial<PostFormData>): Promise<AxiosResponse<PostResponse>> =>
    apiClient.put<PostResponse>(`/posts/${id}`, data),

  remove: (id: number): Promise<AxiosResponse<void>> => apiClient.delete<void>(`/posts/${id}`),
};
