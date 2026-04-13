import { apiClient } from './api-client';
import type {
  AssetResponse,
  AssetListResponse,
  AssetPagedResponse,
  SubFoldersResponse,
} from '../types/asset';
import type { ListParams } from '../types/common';

export const assetsService = {
  getListPaged: (params?: ListParams) =>
    apiClient.get<AssetPagedResponse>('/assets/list/paged', { params }),
  getSubFolders: () => apiClient.get<SubFoldersResponse>('/assets/sub-folders'),
  getById: (id: number | string) => apiClient.get<AssetResponse>(`/assets/id/${id}`),
  searchByName: (name: string, params?: ListParams) =>
    apiClient.get<AssetPagedResponse>(`/assets/${encodeURIComponent(name)}/paged`, { params }),
  searchBySubFolderAndName: (subFolder: string, name: string, params?: ListParams) =>
    apiClient.get<AssetPagedResponse>(
      `/assets/${encodeURIComponent(subFolder)}/${encodeURIComponent(name)}/paged`,
      { params }
    ),
  upload: (file: { uri: string; type: string; name: string }, subFolder?: string) => {
    const formData = new FormData();
    formData.append('file', file as unknown as Blob);
    if (subFolder) formData.append('subFolder', subFolder);
    return apiClient.post<AssetResponse>('/assets', formData, {
      headers: { 'Content-Type': 'multipart/form-data' },
    });
  },
  uploadMulti: (files: { uri: string; type: string; name: string }[], subFolder?: string) => {
    const formData = new FormData();
    files.forEach((file) => formData.append('files', file as unknown as Blob));
    if (subFolder) formData.append('subFolder', subFolder);
    return apiClient.post<AssetListResponse>('/assets/multi', formData, {
      headers: { 'Content-Type': 'multipart/form-data' },
    });
  },
  update: (id: number | string, file: { uri: string; type: string; name: string }) => {
    const formData = new FormData();
    formData.append('file', file as unknown as Blob);
    return apiClient.put<AssetResponse>(`/assets/${id}`, formData, {
      headers: { 'Content-Type': 'multipart/form-data' },
    });
  },
  remove: (id: number | string) => apiClient.delete(`/assets/${id}`),
};
