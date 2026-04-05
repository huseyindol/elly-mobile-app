export type LoginType = 'admin' | 'tenant';

export interface LoginCredentials {
  usernameOrEmail: string;
  password: string;
  tenantId?: string;
  loginType?: LoginType;
}

export interface LoginResponse {
  token: string;
  refreshToken: string;
  type: string;
  userId: number;
  username: string;
  email: string;
  userCode: string;
  expiredDate: number;
}

export interface RefreshTokenResponse {
  token: string;
  refreshToken: string;
}

export interface AuthUser {
  userId: number;
  username: string;
  email: string;
  userCode: string;
}

export interface TokenDecodeResponse {
  username: string;
  userId: number;
  tenantId?: string;
  exp: number;
}
