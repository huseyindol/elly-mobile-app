import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { bannersService } from '../services/banners';
import type { BannerItem, BannerFormData } from '../types/banner';
import type { ListParams } from '../types/common';

const STALE_TIME = 1000 * 60 * 2;

export const BANNER_KEYS = {
  all: ['banners'] as const,
  lists: () => [...BANNER_KEYS.all, 'list'] as const,
  list: (params?: ListParams) => [...BANNER_KEYS.lists(), params] as const,
  details: () => [...BANNER_KEYS.all, 'detail'] as const,
  detail: (id: string) => [...BANNER_KEYS.details(), id] as const,
};

export const useBannerList = (params?: ListParams) =>
  useQuery({
    queryKey: BANNER_KEYS.list(params),
    queryFn: () => bannersService.getList(params).then((res) => res.data),
    staleTime: STALE_TIME,
  });

export const useBanner = (id: string) =>
  useQuery({
    queryKey: BANNER_KEYS.detail(id),
    queryFn: () => bannersService.getById(id).then((res) => res.data),
    staleTime: STALE_TIME,
    enabled: Boolean(id),
  });

export const useCreateBanner = () => {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (data: BannerFormData) => bannersService.create(data).then((res) => res.data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: BANNER_KEYS.lists() });
    },
  });
};

export const useUpdateBanner = () => {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: ({ id, data }: { id: string; data: Partial<BannerFormData> }) =>
      bannersService.update(id, data).then((res) => res.data),
    onSuccess: (_result: BannerItem, { id }: { id: string; data: Partial<BannerFormData> }) => {
      queryClient.invalidateQueries({ queryKey: BANNER_KEYS.lists() });
      queryClient.invalidateQueries({ queryKey: BANNER_KEYS.detail(id) });
    },
  });
};

export const useDeleteBanner = () => {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (id: string) => bannersService.remove(id).then((res) => res.data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: BANNER_KEYS.lists() });
    },
  });
};
