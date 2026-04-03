import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { pagesService } from '../services/pages';
import type { PageItem, PageFormData } from '../types/page';
import type { ListParams } from '../types/common';

const STALE_TIME = 1000 * 60 * 2;

export const PAGE_KEYS = {
  all: ['pages'] as const,
  lists: () => [...PAGE_KEYS.all, 'list'] as const,
  list: (params?: ListParams) => [...PAGE_KEYS.lists(), params] as const,
  details: () => [...PAGE_KEYS.all, 'detail'] as const,
  detail: (id: string) => [...PAGE_KEYS.details(), id] as const,
};

export const usePageList = (params?: ListParams) =>
  useQuery({
    queryKey: PAGE_KEYS.list(params),
    queryFn: () => pagesService.getList(params).then((res) => res.data),
    staleTime: STALE_TIME,
  });

export const usePage = (id: string) =>
  useQuery({
    queryKey: PAGE_KEYS.detail(id),
    queryFn: () => pagesService.getById(id).then((res) => res.data),
    staleTime: STALE_TIME,
    enabled: Boolean(id),
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
    mutationFn: ({ id, data }: { id: string; data: Partial<PageFormData> }) =>
      pagesService.update(id, data).then((res) => res.data),
    onSuccess: (_result: PageItem, { id }: { id: string; data: Partial<PageFormData> }) => {
      queryClient.invalidateQueries({ queryKey: PAGE_KEYS.lists() });
      queryClient.invalidateQueries({ queryKey: PAGE_KEYS.detail(id) });
    },
  });
};

export const useDeletePage = () => {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (id: string) => pagesService.remove(id).then((res) => res.data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: PAGE_KEYS.lists() });
    },
  });
};
