import { useQuery, useMutation, useQueryClient, useInfiniteQuery } from '@tanstack/react-query';
import { contentsService } from '../services/contents';
import type { ContentInput } from '../types/content';
import type { ListParams } from '../types/common';

const STALE_TIME = 1000 * 60 * 2;

export const CONTENT_KEYS = {
  all: ['contents'] as const,
  lists: () => ['contents', 'list'] as const,
  detail: (id: string) => ['contents', 'detail', id] as const,
  section: (sectionKey: string) => ['contents', 'section', sectionKey] as const,
};

export const useContentList = () =>
  useQuery({
    queryKey: CONTENT_KEYS.lists(),
    queryFn: () =>
      contentsService.getList({ sort: 'basicInfo.sortOrder,asc' }).then((res) => res.data),
    staleTime: STALE_TIME,
  });

export const useContentsPaged = (params?: ListParams) =>
  useQuery({
    queryKey: [...CONTENT_KEYS.lists(), 'paged', params] as const,
    queryFn: () =>
      contentsService
        .getList({ sort: 'basicInfo.sortOrder,asc', ...params })
        .then((res) => res.data),
    staleTime: STALE_TIME,
  });

export const useContentBySection = (sectionKey: string) =>
  useQuery({
    queryKey: CONTENT_KEYS.section(sectionKey),
    queryFn: () => contentsService.getBySection(sectionKey).then((res) => res.data),
    staleTime: STALE_TIME,
    enabled: Boolean(sectionKey),
  });

export const useContent = (id: string) =>
  useQuery({
    queryKey: CONTENT_KEYS.detail(id),
    queryFn: () => contentsService.getById(id).then((res) => res.data),
    staleTime: STALE_TIME,
    enabled: Boolean(id),
  });

export const useCreateContent = () => {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (data: ContentInput) => contentsService.create(data).then((res) => res.data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: CONTENT_KEYS.lists() });
    },
  });
};

export const useUpdateContent = () => {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: ({ id, data }: { id: string; data: Partial<ContentInput> }) =>
      contentsService.update(id, data).then((res) => res.data),
    onSuccess: (_result, { id }) => {
      queryClient.invalidateQueries({ queryKey: CONTENT_KEYS.lists() });
      queryClient.invalidateQueries({ queryKey: CONTENT_KEYS.detail(id) });
    },
  });
};

export const useDeleteContent = () => {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (id: string) => contentsService.remove(id).then((res) => res.data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: CONTENT_KEYS.lists() });
    },
  });
};

export const useInfiniteContents = (search?: string) =>
  useInfiniteQuery({
    queryKey: [...CONTENT_KEYS.lists(), 'infinite', { search }] as const,
    queryFn: ({ pageParam }) => contentsService.getList().then((res) => res.data),
    initialPageParam: 0,
    getNextPageParam: () => undefined,
    staleTime: STALE_TIME,
  });
