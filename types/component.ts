import type { PaginatedResponse } from './common';

export interface ComponentItem {
  id: string;
  name: string;
  type: string;
  isActive: boolean;
  config?: Record<string, unknown>;
  createdAt: string;
  updatedAt: string;
}

export interface ComponentFormData {
  name: string;
  type: string;
  isActive: boolean;
  config?: Record<string, unknown>;
}

export type ComponentListResponse = PaginatedResponse<ComponentItem>;
