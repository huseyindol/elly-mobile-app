import type { BaseApiResponse, PagedResponse } from './common';

export type FieldType =
  | 'text'
  | 'email'
  | 'number'
  | 'select'
  | 'checkbox'
  | 'multi_checkbox'
  | 'radio'
  | 'textarea'
  | 'date'
  | 'phone'
  | 'url';

export type FormLayout = 'single' | 'vertical' | 'wizard';

export type ConditionOperator = 'EQUALS' | 'NOT_EQUALS' | 'GT' | 'LT';

export interface ValidationRule {
  min?: number;
  max?: number;
  pattern?: string;
}

export interface ConditionRule {
  field: string;
  operator: ConditionOperator;
  value: string | number | boolean;
}

export interface FieldOption {
  label: string;
  value: string;
}

export interface FormField {
  id: string;
  type: FieldType;
  label: string;
  required?: boolean;
  placeholder?: string;
  validation?: ValidationRule;
  condition?: ConditionRule;
  options?: FieldOption[];
  step?: string;
}

export interface FormConfig {
  layout?: FormLayout;
  submitButtonText?: string;
}

export interface FormStep {
  id: string;
  title: string;
  description?: string;
}

export interface FormSchemaDefinition {
  config?: FormConfig;
  fields: FormField[];
  steps?: FormStep[];
}

export interface FormSchema {
  id: number;
  title: string;
  version: number;
  active: boolean;
  schema: FormSchemaDefinition;
  createdAt?: string;
  updatedAt?: string;
}

export interface FormSchemaFormData {
  title: string;
  version?: number;
  active: boolean;
  schema: FormSchemaDefinition;
}

export interface FormSubmission {
  id: number;
  formId: number;
  payload: Record<string, unknown>;
  submittedAt: string;
}

export interface FormSchemaSummary {
  id: number;
  title: string;
  version: number;
  active: boolean;
}

export type FormSchemaResponse = BaseApiResponse<FormSchema>;
export type FormSchemaListResponse = BaseApiResponse<FormSchema[]>;
export type FormSchemaPagedResponse = BaseApiResponse<PagedResponse<FormSchema>>;
export type FormSubmissionListResponse = BaseApiResponse<FormSubmission[]>;
export type FormSubmissionPagedResponse = BaseApiResponse<PagedResponse<FormSubmission>>;
