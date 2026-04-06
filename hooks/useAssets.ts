import { useQuery, useMutation, useQueryClient, useInfiniteQuery } from '@tanstack/react-query';
import { assetsService } from '../services/assets';
import type { ListParams } from '../types/common';

const STALE_TIME = 1000 * 60 * 2;
const SUBFOLDERS_STALE_TIME = 1000 * 60 * 5;

export const ASSET_KEYS = {
  all: ['assets'] as const,
  lists: () => ['assets', 'list'] as const,
  detail: (id: number | string) => ['assets', 'detail', id] as const,
  subFolders: () => ['assets', 'sub-folders'] as const,
};

export const useAssetsPaged = (params?: ListParams) =>
  useQuery({
    queryKey: [...ASSET_KEYS.lists(), 'paged', params] as const,
    queryFn: () => assetsService.getListPaged(params).then((res) => res.data),
    staleTime: STALE_TIME,
  });

export const useAsset = (id: number) =>
  useQuery({
    queryKey: ASSET_KEYS.detail(id),
    queryFn: () => assetsService.getById(id).then((res) => res.data),
    staleTime: STALE_TIME,
    enabled: id > 0,
  });

export const useSubFolders = () =>
  useQuery({
    queryKey: ASSET_KEYS.subFolders(),
    queryFn: () => assetsService.getSubFolders().then((res) => res.data),
    staleTime: SUBFOLDERS_STALE_TIME,
  });

export const useUploadAsset = () => {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: ({
      file,
      subFolder,
    }: {
      file: { uri: string; type: string; name: string };
      subFolder?: string;
    }) => assetsService.upload(file, subFolder).then((res) => res.data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ASSET_KEYS.lists() });
    },
  });
};

export const useUploadMultiAssets = () => {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: ({
      files,
      subFolder,
    }: {
      files: Array<{ uri: string; type: string; name: string }>;
      subFolder?: string;
    }) => assetsService.uploadMulti(files, subFolder).then((res) => res.data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ASSET_KEYS.lists() });
    },
  });
};

export const useUpdateAsset = () => {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: ({
      id,
      file,
    }: {
      id: number | string;
      file: { uri: string; type: string; name: string };
    }) => assetsService.update(id, file).then((res) => res.data),
    onSuccess: (_result, { id }) => {
      queryClient.invalidateQueries({ queryKey: ASSET_KEYS.lists() });
      queryClient.invalidateQueries({ queryKey: ASSET_KEYS.detail(id) });
    },
  });
};

export const useDeleteAsset = () => {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (id: number | string) => assetsService.remove(id).then((res) => res.data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ASSET_KEYS.lists() });
    },
  });
};

export const useInfiniteAssets = (search?: string, subFolder?: string) =>
  useInfiniteQuery({
    queryKey: [...ASSET_KEYS.lists(), 'infinite', { search, subFolder }] as const,
    queryFn: ({ pageParam }) => {
      const base = subFolder && subFolder !== 'all'
        ? assetsService.searchBySubFolderAndName(subFolder, search ?? '', { page: pageParam as number, size: 20 })
        : search
        ? assetsService.searchByName(search, { page: pageParam as number, size: 20 })
        : assetsService.getListPaged({ page: pageParam as number, size: 20 });
      return base.then((res) => res.data);
    },
    initialPageParam: 0,
    getNextPageParam: (lastPage) => {
      const d = lastPage.data;
      return d.last ? undefined : d.page + 1;
    },
    staleTime: STALE_TIME,
  });
