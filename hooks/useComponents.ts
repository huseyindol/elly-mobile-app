import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { componentsService } from '../services/components';
import type { ComponentFormData } from '../types/component';
import type { ListParams } from '../types/common';

const STALE_TIME = 1000 * 60 * 2;

export const COMPONENT_KEYS = {
  all: ['components'] as const,
  lists: () => ['components', 'list'] as const,
  detail: (id: number) => ['components', 'detail', id] as const,
};

export const useComponentList = (params?: ListParams) =>
  useQuery({
    queryKey: [...COMPONENT_KEYS.lists(), params] as const,
    queryFn: () => componentsService.getList().then((res) => res.data),
    staleTime: STALE_TIME,
  });

export const useComponentsPaged = (params?: ListParams) =>
  useQuery({
    queryKey: [...COMPONENT_KEYS.lists(), 'paged', params] as const,
    queryFn: () => componentsService.getListPaged(params).then((res) => res.data),
    staleTime: STALE_TIME,
  });

export const useComponent = (id: number) =>
  useQuery({
    queryKey: COMPONENT_KEYS.detail(id),
    queryFn: () => componentsService.getById(id).then((res) => res.data),
    staleTime: STALE_TIME,
    enabled: id > 0,
  });

export const useCreateComponent = () => {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (data: ComponentFormData) =>
      componentsService.create(data).then((res) => res.data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: COMPONENT_KEYS.lists() });
    },
  });
};

export const useUpdateComponent = () => {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: ({ id, data }: { id: number; data: Partial<ComponentFormData> }) =>
      componentsService.update(id, data).then((res) => res.data),
    onSuccess: (_result, { id }) => {
      queryClient.invalidateQueries({ queryKey: COMPONENT_KEYS.lists() });
      queryClient.invalidateQueries({ queryKey: COMPONENT_KEYS.detail(id) });
    },
  });
};

export const useDeleteComponent = () => {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (id: number) => componentsService.remove(id).then((res) => res.data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: COMPONENT_KEYS.lists() });
    },
  });
};
