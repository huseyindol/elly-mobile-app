import type { PaginatedResponse } from './common';

export type PostStatus = 'draft' | 'published' | 'archived';

export interface PostItem {
  id: string;
  title: string;
  status: PostStatus;
  slug: string;
  excerpt?: string;
  createdAt: string;
  updatedAt: string;
}

export interface PostFormData {
  title: string;
  slug: string;
  status: PostStatus;
  excerpt?: string;
  content?: string;
}

export type PostListResponse = PaginatedResponse<PostItem>;
