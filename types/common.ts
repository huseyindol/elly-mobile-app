// Shared API response wrappers, pagination types, and error shapes used across all services.

export interface BaseApiResponse<T = unknown> {
  result: boolean;
  data: T;
  message?: string | null;
  errorCode?: string;
  error?: string;
  status?: number;
}

export interface PagedResponse<T> {
  content: T[];
  page: number;
  size: number;
  totalElements: number;
  totalPages: number;
  first: boolean;
  last: boolean;
}

export interface ListParams {
  page?: number;
  size?: number;
  sort?: string;
  search?: string;
}

export interface ApiError {
  result: false;
  status: number;
  error: string;
  errorCode: string;
  message: string;
}
