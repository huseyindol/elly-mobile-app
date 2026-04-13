// Architectural decision: A single Axios instance is shared across all services.
// Authorization headers are injected at request time via an interceptor so that
// the token is always read from the latest Zustand store state.
// tenantId is injected via the X-Tenant-ID header when present in auth store.
// 401 responses trigger a token refresh attempt using the stored refreshToken.
// If the refresh succeeds, the original request is retried transparently.
// If the refresh fails (or no refreshToken exists), auth state is cleared
// and the user is redirected to the login screen.

import axios, { AxiosError, type AxiosResponse, type InternalAxiosRequestConfig } from 'axios';
import { router } from 'expo-router';
import { ENV } from '../constants/env';
import { useAuthStore } from '../store/authStore';

export const apiClient = axios.create({
  baseURL: ENV.API_URL,
  headers: { 'Content-Type': 'application/json' },
  timeout: 15000,
});

// ── Request interceptor ────────────────────────────────────────────────────────
apiClient.interceptors.request.use(
  (config: InternalAxiosRequestConfig) => {
    const { token, tenantId } = useAuthStore.getState();
    if (token) config.headers.set('Authorization', `Bearer ${token}`);
    if (tenantId) config.headers.set('X-Tenant-ID', tenantId);

    if (__DEV__) {
      console.warn(
        `🔵 ${config.method?.toUpperCase()} ${config.baseURL}${config.url}`,
        config.data ?? ''
      );
    }
    return config;
  },
  (error: AxiosError) => Promise.reject(error)
);

// ── Response logger (dev only) ──────────────────────────────────────────────
apiClient.interceptors.response.use(
  (response: AxiosResponse) => {
    if (__DEV__) {
      console.warn(`🟢 ${response.status} ${response.config.url}`, response.data);
    }
    return response;
  },
  (error: AxiosError) => {
    if (__DEV__) {
      console.warn(
        `🔴 ${error.response?.status ?? 'NETWORK'} ${error.config?.url}`,
        error.response?.data ?? error.message
      );
    }
    return Promise.reject(error);
  }
);

// ── Token refresh state ────────────────────────────────────────────────────────
// Prevents multiple simultaneous refresh requests when several requests 401 at once.
let isRefreshing = false;
let failedQueue: {
  resolve: (value: unknown) => void;
  reject: (reason: unknown) => void;
}[] = [];

function processQueue(error: unknown, token: string | null = null) {
  failedQueue.forEach(({ resolve, reject }) => {
    if (error) reject(error);
    else resolve(token);
  });
  failedQueue = [];
}

function logoutAndRedirect() {
  useAuthStore.getState().logout();
  router.replace('/(auth)/login');
}

// ── Response interceptor ───────────────────────────────────────────────────────
apiClient.interceptors.response.use(
  (response: AxiosResponse) => response,
  async (error: AxiosError) => {
    const originalRequest = error.config as InternalAxiosRequestConfig & {
      _retry?: boolean;
    };

    if (error.response?.status !== 401 || originalRequest._retry) {
      return Promise.reject(error);
    }

    const { refreshToken, updateTokens } = useAuthStore.getState();

    // No refreshToken → cannot renew, log out immediately.
    if (!refreshToken) {
      logoutAndRedirect();
      return Promise.reject(error);
    }

    // If a refresh is already in flight, queue this request until it resolves.
    if (isRefreshing) {
      return new Promise((resolve, reject) => {
        failedQueue.push({ resolve, reject });
      }).then((token) => {
        originalRequest.headers.set('Authorization', `Bearer ${token as string}`);
        return apiClient(originalRequest);
      });
    }

    originalRequest._retry = true;
    isRefreshing = true;

    try {
      // Use a plain axios call (not apiClient) to avoid interceptor loops.
      const res = await axios.post<{
        result: boolean;
        data: { token: string; refreshToken: string };
      }>(`${ENV.API_URL}/auth/refresh`, { refreshToken });

      const { token: newToken, refreshToken: newRefresh } = res.data.data;
      updateTokens(newToken, newRefresh, 0); // expiredDate decoded from new token if needed

      processQueue(null, newToken);
      originalRequest.headers.set('Authorization', `Bearer ${newToken}`);
      return apiClient(originalRequest);
    } catch (refreshError) {
      processQueue(refreshError);
      logoutAndRedirect();
      return Promise.reject(refreshError);
    } finally {
      isRefreshing = false;
    }
  }
);
