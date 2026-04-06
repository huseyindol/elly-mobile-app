import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { pagesService } from '../services/pages';
import type { PageFormData } from '../types/page';
import type { ListParams } from '../types/common';

const STALE_TIME = 1000 * 60 * 2;

export const PAGE_KEYS = {
  all: ['pages'] as const,
  lists: () => ['pages', 'list'] as const,
  detail: (id: number) => ['pages', 'detail', id] as const,
};

export const usePageList = (params?: ListParams) =>
  useQuery({
    queryKey: [...PAGE_KEYS.lists(), params] as const,
    queryFn: () => pagesService.getList().then((res) => res.data),
    staleTime: STALE_TIME,
  });

export const usePagesPaged = (params?: ListParams) =>
  useQuery({
    queryKey: [...PAGE_KEYS.lists(), 'paged', params] as const,
    queryFn: () => pagesService.getListPaged(params).then((res) => res.data),
    staleTime: STALE_TIME,
  });

export const usePage = (id: number) =>
  useQuery({
    queryKey: PAGE_KEYS.detail(id),
    queryFn: () => pagesService.getBySlug(String(id)).then((res) => res.data.data),
    staleTime: STALE_TIME,
    enabled: id > 0,
  });

export const useCreatePage = () => {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (data: PageFormData) => pagesService.create(data).then((res) => res.data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: PAGE_KEYS.lists() });
    },
  });
};

export const useUpdatePage = () => {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: ({ id, data }: { id: number; data: Partial<PageFormData> }) =>
      pagesService.update(id, data).then((res) => res.data),
    onSuccess: (_result, { id }) => {
      queryClient.invalidateQueries({ queryKey: PAGE_KEYS.lists() });
      queryClient.invalidateQueries({ queryKey: PAGE_KEYS.detail(id) });
    },
  });
};

export const useDeletePage = () => {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (id: number) => pagesService.remove(id).then((res) => res.data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: PAGE_KEYS.lists() });
    },
  });
};
