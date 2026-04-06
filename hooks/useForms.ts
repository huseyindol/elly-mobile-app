import { useQuery, useMutation, useQueryClient, useInfiniteQuery } from '@tanstack/react-query';
import { formsService } from '../services/forms';
import type { FormSchemaFormData } from '../types/form';
import type { ListParams } from '../types/common';

const STALE_TIME = 1000 * 60 * 2;

export const FORM_KEYS = {
  all: ['forms'] as const,
  lists: () => ['forms', 'list'] as const,
  detail: (id: number) => ['forms', 'detail', id] as const,
  submissions: (formId: number) => ['forms', 'submissions', formId] as const,
  submissionCount: (formId: number) => ['forms', 'submissions', formId, 'count'] as const,
};

export const useFormList = () =>
  useQuery({
    queryKey: FORM_KEYS.lists(),
    queryFn: () => formsService.getList().then((res) => res.data),
    staleTime: STALE_TIME,
  });

export const useFormsPaged = (params?: ListParams) =>
  useQuery({
    queryKey: [...FORM_KEYS.lists(), 'paged', params] as const,
    queryFn: () => formsService.getListPaged(params).then((res) => res.data),
    staleTime: STALE_TIME,
  });

export const useForm = (id: number) =>
  useQuery({
    queryKey: FORM_KEYS.detail(id),
    queryFn: () => formsService.getById(id).then((res) => res.data),
    staleTime: STALE_TIME,
    enabled: id > 0,
  });

export const useCreateForm = () => {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (data: FormSchemaFormData) =>
      formsService.create(data).then((res) => res.data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: FORM_KEYS.lists() });
    },
  });
};

export const useUpdateForm = () => {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: ({ id, data }: { id: number; data: Partial<FormSchemaFormData> }) =>
      formsService.update(id, data).then((res) => res.data),
    onSuccess: (_result, { id }) => {
      queryClient.invalidateQueries({ queryKey: FORM_KEYS.lists() });
      queryClient.invalidateQueries({ queryKey: FORM_KEYS.detail(id) });
    },
  });
};

export const useDeleteForm = () => {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (id: number) => formsService.remove(id).then((res) => res.data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: FORM_KEYS.lists() });
    },
  });
};

export const useFormSubmissionsPaged = (formId: number, params?: ListParams) =>
  useQuery({
    queryKey: [...FORM_KEYS.submissions(formId), 'paged', params] as const,
    queryFn: () => formsService.getSubmissionsPaged(formId, params).then((res) => res.data),
    staleTime: STALE_TIME,
    enabled: formId > 0,
  });

export const useSubmissionCount = (formId: number) =>
  useQuery({
    queryKey: FORM_KEYS.submissionCount(formId),
    queryFn: () => formsService.getSubmissionCount(formId).then((res) => res.data),
    staleTime: STALE_TIME,
    enabled: formId > 0,
  });

export const useInfiniteForms = (search?: string) =>
  useInfiniteQuery({
    queryKey: [...FORM_KEYS.lists(), 'infinite', { search }] as const,
    queryFn: ({ pageParam }) =>
      formsService.getListPaged({ page: pageParam as number, size: 20, search }).then((res) => res.data),
    initialPageParam: 0,
    getNextPageParam: (lastPage) => {
      const d = lastPage.data;
      return d.last ? undefined : d.page + 1;
    },
    staleTime: STALE_TIME,
  });
