import { useQuery, useMutation, useQueryClient, useInfiniteQuery } from '@tanstack/react-query';
import { postsService } from '../services/posts';
import type { PostFormData } from '../types/post';
import type { ListParams } from '../types/common';

const STALE_TIME = 1000 * 60 * 2;

export const POST_KEYS = {
  all: ['posts'] as const,
  lists: () => ['posts', 'list'] as const,
  detail: (id: number) => ['posts', 'detail', id] as const,
};

export const usePostList = (params?: ListParams) =>
  useQuery({
    queryKey: [...POST_KEYS.lists(), params] as const,
    queryFn: () => postsService.getList().then((res) => res.data),
    staleTime: STALE_TIME,
  });

export const usePostListSummary = () =>
  useQuery({
    queryKey: [...POST_KEYS.lists(), 'summary'] as const,
    queryFn: () => postsService.getListSummary().then((res) => res.data),
    staleTime: STALE_TIME,
  });

export const usePostsPaged = (params?: ListParams) =>
  useQuery({
    queryKey: [...POST_KEYS.lists(), 'paged', params] as const,
    queryFn: () => postsService.getListPaged(params).then((res) => res.data),
    staleTime: STALE_TIME,
  });

export const usePost = (id: number) =>
  useQuery({
    queryKey: POST_KEYS.detail(id),
    queryFn: () => postsService.getById(id).then((res) => res.data.data),
    staleTime: STALE_TIME,
    enabled: id > 0,
  });

export const useCreatePost = () => {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (data: PostFormData) => postsService.create(data).then((res) => res.data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: POST_KEYS.lists() });
    },
  });
};

export const useUpdatePost = () => {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: ({ id, data }: { id: number; data: Partial<PostFormData> }) =>
      postsService.update(id, data).then((res) => res.data),
    onSuccess: (_result, { id }) => {
      queryClient.invalidateQueries({ queryKey: POST_KEYS.lists() });
      queryClient.invalidateQueries({ queryKey: POST_KEYS.detail(id) });
    },
  });
};

export const useDeletePost = () => {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (id: number) => postsService.remove(id).then((res) => res.data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: POST_KEYS.lists() });
    },
  });
};

export const useInfinitePosts = (search?: string) =>
  useInfiniteQuery({
    queryKey: [...POST_KEYS.lists(), 'infinite', { search }] as const,
    queryFn: ({ pageParam }) =>
      postsService
        .getListPaged({ page: pageParam as number, size: 20, search })
        .then((res) => res.data),
    initialPageParam: 0,
    getNextPageParam: (lastPage) => {
      const d = lastPage.data;
      return d.last ? undefined : d.page + 1;
    },
    staleTime: STALE_TIME,
  });
