import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { componentsService } from '../services/components';
import type { ComponentItem, ComponentFormData } from '../types/component';
import type { ListParams } from '../types/common';

const STALE_TIME = 1000 * 60 * 2;

export const COMPONENT_KEYS = {
  all: ['components'] as const,
  lists: () => [...COMPONENT_KEYS.all, 'list'] as const,
  list: (params?: ListParams) => [...COMPONENT_KEYS.lists(), params] as const,
  details: () => [...COMPONENT_KEYS.all, 'detail'] as const,
  detail: (id: string) => [...COMPONENT_KEYS.details(), id] as const,
};

export const useComponentList = (params?: ListParams) =>
  useQuery({
    queryKey: COMPONENT_KEYS.list(params),
    queryFn: () => componentsService.getList(params).then((res) => res.data),
    staleTime: STALE_TIME,
  });

export const useComponent = (id: string) =>
  useQuery({
    queryKey: COMPONENT_KEYS.detail(id),
    queryFn: () => componentsService.getById(id).then((res) => res.data),
    staleTime: STALE_TIME,
    enabled: Boolean(id),
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
    mutationFn: ({ id, data }: { id: string; data: Partial<ComponentFormData> }) =>
      componentsService.update(id, data).then((res) => res.data),
    onSuccess: (_result: ComponentItem, { id }: { id: string; data: Partial<ComponentFormData> }) => {
      queryClient.invalidateQueries({ queryKey: COMPONENT_KEYS.lists() });
      queryClient.invalidateQueries({ queryKey: COMPONENT_KEYS.detail(id) });
    },
  });
};

export const useDeleteComponent = () => {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (id: string) => componentsService.remove(id).then((res) => res.data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: COMPONENT_KEYS.lists() });
    },
  });
};
