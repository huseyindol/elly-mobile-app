import type { AxiosResponse } from 'axios';
import { apiClient } from './api-client';
import type {
  LoginCredentials,
  LoginResponse,
  RefreshTokenResponse,
  TokenDecodeResponse,
} from '../types/auth';
import type { BaseApiResponse } from '../types/common';

export const authService = {
  login: (
    credentials: LoginCredentials,
  ): Promise<AxiosResponse<BaseApiResponse<LoginResponse>>> =>
    apiClient.post<BaseApiResponse<LoginResponse>>('/auth/login', credentials),

  logout: (): Promise<AxiosResponse<void>> => apiClient.post<void>('/auth/logout'),

  refreshToken: (
    token: string,
  ): Promise<AxiosResponse<BaseApiResponse<RefreshTokenResponse>>> =>
    apiClient.post<BaseApiResponse<RefreshTokenResponse>>('/auth/refresh', {
      refreshToken: token,
    }),

  decodeToken: (): Promise<AxiosResponse<BaseApiResponse<TokenDecodeResponse>>> =>
    apiClient.get<BaseApiResponse<TokenDecodeResponse>>('/auth/decode'),
};
