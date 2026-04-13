// Elly Mobile App — FormField component
// react-hook-form Controller wrapper around the Input component.
// Handles field state, error messages, and validation rules.

import React from 'react';
import {
  Controller,
  type Control,
  type ControllerRenderProps,
  type ControllerFieldState,
  type FieldValues,
  type Path,
  type RegisterOptions,
} from 'react-hook-form';
import { Input } from '../ui/Input';

export interface FormFieldProps<T extends FieldValues> {
  control: Control<T>;
  name: Path<T>;
  label?: string;
  placeholder?: string;
  rules?: RegisterOptions<T, Path<T>>;
  secureTextEntry?: boolean;
  multiline?: boolean;
  numberOfLines?: number;
  rightElement?: React.ReactNode;
}

export function FormField<T extends FieldValues>({
  control,
  name,
  label,
  placeholder,
  rules,
  secureTextEntry,
  multiline,
  numberOfLines,
  rightElement,
}: FormFieldProps<T>) {
  return (
    <Controller
      control={control}
      name={name}
      rules={rules}
      render={({
        field,
        fieldState,
      }: {
        field: ControllerRenderProps<T, Path<T>>;
        fieldState: ControllerFieldState;
      }) => (
        <Input
          label={label}
          placeholder={placeholder}
          value={(field.value as string) ?? ''}
          onChangeText={field.onChange}
          error={fieldState.error?.message}
          secureTextEntry={secureTextEntry}
          multiline={multiline}
          numberOfLines={numberOfLines}
          rightElement={rightElement}
        />
      )}
    />
  );
}
