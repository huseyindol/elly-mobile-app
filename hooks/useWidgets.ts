// Architectural decision: React Query hooks for widgets mirror the pattern used
// across all resource hooks (pages, posts, banners, components). Reads use useQuery
// with a 2-minute staleTime; writes use useMutation and invalidate the relevant
// query keys on success so the UI stays in sync without a manual refetch.

import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { widgetsService } from '../services/widgets';
import type { WidgetFormData } from '../types/widget';
import type { ListParams } from '../types/common';

const STALE_TIME = 1000 * 60 * 2;

export const WIDGET_KEYS = {
  all: ['widgets'] as const,
  lists: () => [...WIDGET_KEYS.all, 'list'] as const,
  list: (params?: ListParams) => [...WIDGET_KEYS.lists(), params] as const,
  details: () => [...WIDGET_KEYS.all, 'detail'] as const,
  detail: (id: string) => [...WIDGET_KEYS.details(), id] as const,
};

export const useWidgetList = (params?: ListParams) =>
  useQuery({
    queryKey: WIDGET_KEYS.list(params),
    queryFn: () => widgetsService.getList(params).then((res) => res.data),
    staleTime: STALE_TIME,
  });

export const useWidget = (id: string) =>
  useQuery({
    queryKey: WIDGET_KEYS.detail(id),
    queryFn: () => widgetsService.getById(id).then((res) => res.data),
    staleTime: STALE_TIME,
    enabled: Boolean(id),
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
    mutationFn: ({ id, data }: { id: string; data: Partial<WidgetFormData> }) =>
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
    mutationFn: (id: string) => widgetsService.remove(id).then((res) => res.data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: WIDGET_KEYS.lists() });
    },
  });
};
