import type { PaginatedResponse } from './common';

export interface WidgetItem {
  id: string;
  name: string;
  type: string;
  config: Record<string, unknown>;
  isActive: boolean;
  createdAt: string;
  updatedAt: string;
}

export interface WidgetFormData {
  name: string;
  type: string;
  config: Record<string, unknown>;
  isActive: boolean;
}

export type WidgetListResponse = PaginatedResponse<WidgetItem>;
