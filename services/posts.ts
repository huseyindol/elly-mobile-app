import type { AxiosResponse } from 'axios';
import { apiClient } from './api-client';
import type { PostItem, PostFormData, PostListResponse } from '../types/post';
import type { ListParams } from '../types/common';

export const postsService = {
  getList: (params?: ListParams): Promise<AxiosResponse<PostListResponse>> =>
    apiClient.get<PostListResponse>('/posts', { params }),

  getById: (id: string): Promise<AxiosResponse<PostItem>> =>
    apiClient.get<PostItem>(`/posts/${id}`),

  create: (data: PostFormData): Promise<AxiosResponse<PostItem>> =>
    apiClient.post<PostItem>('/posts', data),

  update: (id: string, data: Partial<PostFormData>): Promise<AxiosResponse<PostItem>> =>
    apiClient.patch<PostItem>(`/posts/${id}`, data),

  remove: (id: string): Promise<AxiosResponse<void>> =>
    apiClient.delete<void>(`/posts/${id}`),
};
