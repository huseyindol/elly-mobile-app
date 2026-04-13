import { apiClient } from './api-client';
import type {
  FormSchemaResponse,
  FormSchemaListResponse,
  FormSchemaPagedResponse,
  FormSchemaFormData,
  FormSubmissionListResponse,
  FormSubmissionPagedResponse,
} from '../types/form';
import type { BaseApiResponse, ListParams } from '../types/common';

export const formsService = {
  getList: () => apiClient.get<FormSchemaListResponse>('/forms/list'),

  getListPaged: (params?: ListParams) =>
    apiClient.get<FormSchemaPagedResponse>('/forms/list/paged', { params }),

  getActive: () => apiClient.get<FormSchemaListResponse>('/forms/list/active'),

  getById: (id: number) => apiClient.get<FormSchemaResponse>(`/forms/${id}`),

  create: (data: FormSchemaFormData) => apiClient.post<FormSchemaResponse>('/forms', data),

  update: (id: number, data: Partial<FormSchemaFormData>) =>
    apiClient.put<FormSchemaResponse>(`/forms/${id}`, data),

  remove: (id: number) => apiClient.delete<void>(`/forms/${id}`),

  getSubmissionsPaged: (formId: number, params?: ListParams) =>
    apiClient.get<FormSubmissionPagedResponse>(`/forms/${formId}/submissions/paged`, { params }),

  getSubmission: (submissionId: number) =>
    apiClient.get<FormSubmissionListResponse>(`/forms/submissions/${submissionId}`),

  getSubmissionCount: (formId: number) =>
    apiClient.get<BaseApiResponse<number>>(`/forms/${formId}/submissions/count`),

  submitForm: (formId: number, payload: Record<string, unknown>) =>
    apiClient.post<BaseApiResponse<void>>(`/forms/${formId}/submit`, payload),
};
