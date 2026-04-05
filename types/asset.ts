import type { BaseApiResponse, PagedResponse } from './common';

export interface AssetItem {
  id: number;
  path: string;
  type: string;
  name: string;
  extension: string;
  subFolder?: string;
}

export type AssetResponse = BaseApiResponse<AssetItem>;
export type AssetListResponse = BaseApiResponse<AssetItem[]>;
export type AssetPagedResponse = BaseApiResponse<PagedResponse<AssetItem>>;
export type SubFoldersResponse = BaseApiResponse<string[]>;
