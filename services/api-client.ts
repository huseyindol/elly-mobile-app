// Architectural decision: A single Axios instance is shared across all services.
// Authorization headers are injected at request time via an interceptor so that
// the token is always read from the latest Zustand store state.
// tenantId is injected via the X-Tenant-ID header when present in auth store.
// 401 responses clear auth state and redirect to the login screen via Expo Router.

import axios, { AxiosError, type AxiosResponse, type InternalAxiosRequestConfig } from 'axios';
import { router } from 'expo-router';
import { ENV } from '../constants/env';
import { useAuthStore } from '../store/authStore';

export const apiClient = axios.create({
  baseURL: ENV.API_URL,
  headers: {
    'Content-Type': 'application/json',
  },
  timeout: 15000,
});

// Attach the current auth token and optional tenant ID to every outgoing request.
apiClient.interceptors.request.use(
  (config: InternalAxiosRequestConfig) => {
    const { token, tenantId } = useAuthStore.getState();
    if (token) {
      config.headers.set('Authorization', `Bearer ${token}`);
    }
    if (tenantId) {
      config.headers.set('X-Tenant-ID', tenantId);
    }
    return config;
  },
  (error: AxiosError) => Promise.reject(error),
);

// On 401, clear auth state and redirect to login.
apiClient.interceptors.response.use(
  (response: AxiosResponse) => response,
  (error: AxiosError) => {
    if (error.response?.status === 401) {
      useAuthStore.getState().logout();
      // Navigate outside of the React render cycle using the imperative API.
      router.replace('/(auth)/login');
    }
    return Promise.reject(error);
  },
);
