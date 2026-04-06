// Architectural decision: React Query hooks for widgets mirror the pattern used
// across all resource hooks (pages, posts, banners, components). Reads use useQuery
// with a 2-minute staleTime; writes use useMutation and invalidate the relevant
// query keys on success so the UI stays in sync without a manual refetch.

import { useQuery, useMutation, useQueryClient, useInfiniteQuery } from '@tanstack/react-query';
import { widgetsService } from '../services/widgets';
import type { WidgetFormData } from '../types/widget';
import type { ListParams } from '../types/common';

const STALE_TIME = 1000 * 60 * 2;

export const WIDGET_KEYS = {
  all: ['widgets'] as const,
  lists: () => ['widgets', 'list'] as const,
  detail: (id: number) => ['widgets', 'detail', id] as const,
};

export const useWidgetList = (params?: ListParams) =>
  useQuery({
    queryKey: [...WIDGET_KEYS.lists(), params] as const,
    queryFn: () => widgetsService.getList().then((res) => res.data),
    staleTime: STALE_TIME,
  });

export const useWidgetsPaged = (params?: ListParams) =>
  useQuery({
    queryKey: [...WIDGET_KEYS.lists(), 'paged', params] as const,
    queryFn: () => widgetsService.getListPaged(params).then((res) => res.data),
    staleTime: STALE_TIME,
  });

export const useWidget = (id: number) =>
  useQuery({
    queryKey: WIDGET_KEYS.detail(id),
    queryFn: () => widgetsService.getById(id).then((res) => res.data),
    staleTime: STALE_TIME,
    enabled: id > 0,
  });

export const useCreateWidget = () => {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (data: WidgetFormData) => widgetsService.create(data).then((res) => res.data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: WIDGET_KEYS.lists() });
    },
  });
};

export const useUpdateWidget = () => {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: ({ id, data }: { id: number; data: Partial<WidgetFormData> }) =>
      widgetsService.update(id, data).then((res) => res.data),
    onSuccess: (_result, { id }) => {
      queryClient.invalidateQueries({ queryKey: WIDGET_KEYS.lists() });
      queryClient.invalidateQueries({ queryKey: WIDGET_KEYS.detail(id) });
    },
  });
};

export const useDeleteWidget = () => {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (id: number) => widgetsService.remove(id).then((res) => res.data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: WIDGET_KEYS.lists() });
    },
  });
};

export const useInfiniteWidgets = (search?: string) =>
  useInfiniteQuery({
    queryKey: [...WIDGET_KEYS.lists(), 'infinite', { search }] as const,
    queryFn: ({ pageParam }) =>
      widgetsService.getListPaged({ page: pageParam as number, size: 20, search }).then((res) => res.data),
    initialPageParam: 0,
    getNextPageParam: (lastPage) => {
      const d = lastPage.data;
      return d.last ? undefined : d.page + 1;
    },
    staleTime: STALE_TIME,
  });
