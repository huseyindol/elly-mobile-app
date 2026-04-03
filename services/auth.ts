import type { AxiosResponse } from 'axios';
import { apiClient } from './api-client';
import type { AuthUser } from '../store/authStore';

export interface LoginCredentials {
  email: string;
  password: string;
}

export interface LoginResponse {
  token: string;
  refreshToken: string;
  user: AuthUser;
}

export interface RefreshTokenResponse {
  token: string;
  refreshToken: string;
}

export const authService = {
  login: (credentials: LoginCredentials): Promise<AxiosResponse<LoginResponse>> =>
    apiClient.post<LoginResponse>('/auth/login', credentials),

  logout: (): Promise<AxiosResponse<void>> =>
    apiClient.post<void>('/auth/logout'),

  refreshToken: (refreshToken: string): Promise<AxiosResponse<RefreshTokenResponse>> =>
    apiClient.post<RefreshTokenResponse>('/auth/refresh', { refreshToken }),
};
