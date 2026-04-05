import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { bannersService } from '../services/banners';
import type { BannerFormData, BannerImageFiles } from '../types/banner';
import type { ListParams } from '../types/common';

const STALE_TIME = 1000 * 60 * 2;

export const BANNER_KEYS = {
  all: ['banners'] as const,
  lists: () => ['banners', 'list'] as const,
  detail: (id: number) => ['banners', 'detail', id] as const,
};

export const useBannerList = (params?: ListParams) =>
  useQuery({
    queryKey: [...BANNER_KEYS.lists(), params] as const,
    queryFn: () => bannersService.getList().then((res) => res.data),
    staleTime: STALE_TIME,
  });

export const useBannersPaged = (params?: ListParams) =>
  useQuery({
    queryKey: [...BANNER_KEYS.lists(), 'paged', params] as const,
    queryFn: () => bannersService.getListPaged(params).then((res) => res.data),
    staleTime: STALE_TIME,
  });

export const useBanner = (id: number) =>
  useQuery({
    queryKey: BANNER_KEYS.detail(id),
    queryFn: () => bannersService.getById(id).then((res) => res.data),
    staleTime: STALE_TIME,
    enabled: id > 0,
  });

export const useCreateBanner = () => {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: ({ data, imageFiles }: { data: BannerFormData; imageFiles?: BannerImageFiles }) =>
      bannersService.create(data, imageFiles).then((res) => res.data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: BANNER_KEYS.lists() });
    },
  });
};

export const useUpdateBanner = () => {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: ({
      id,
      data,
      imageFiles,
    }: {
      id: number;
      data: Partial<BannerFormData>;
      imageFiles?: BannerImageFiles;
    }) => bannersService.update(id, data, imageFiles).then((res) => res.data),
    onSuccess: (_result, { id }) => {
      queryClient.invalidateQueries({ queryKey: BANNER_KEYS.lists() });
      queryClient.invalidateQueries({ queryKey: BANNER_KEYS.detail(id) });
    },
  });
};

export const useDeleteBanner = () => {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (id: number) => bannersService.remove(id).then((res) => res.data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: BANNER_KEYS.lists() });
    },
  });
};
