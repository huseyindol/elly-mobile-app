import { useState } from 'react';
import { StyleSheet, Text, TextInput, View, type TextInputProps } from 'react-native';
import { useThemeColor } from '../../hooks/useThemeColor';

export interface InputProps extends Pick<
  TextInputProps,
  'keyboardType' | 'autoCapitalize' | 'autoCorrect' | 'editable'
> {
  label?: string;
  placeholder?: string;
  value: string;
  onChangeText: (text: string) => void;
  onBlur?: (e: Parameters<NonNullable<TextInputProps['onBlur']>>[0]) => void;
  error?: string;
  secureTextEntry?: boolean;
  multiline?: boolean;
  numberOfLines?: number;
  rightElement?: React.ReactNode;
}

export function Input({
  label,
  placeholder,
  value,
  onChangeText,
  onBlur,
  error,
  secureTextEntry = false,
  multiline = false,
  numberOfLines = 1,
  rightElement,
  editable = true,
  ...rest
}: InputProps) {
  const [focused, setFocused] = useState(false);
  const { colors, isDark } = useThemeColor();

  const borderColor = error ? '#EF4444' : focused ? '#4F46E5' : isDark ? '#374151' : '#D1D5DB';

  const inputHeight = multiline ? numberOfLines * 24 + 24 : 48;

  return (
    <View style={styles.container}>
      {label || rightElement ? (
        <View style={styles.labelRow}>
          {label ? (
            <Text style={[styles.label, { color: colors.text }]}>{label}</Text>
          ) : (
            <View style={{ flex: 1 }} />
          )}
          {rightElement ? <View style={styles.rightElement}>{rightElement}</View> : null}
        </View>
      ) : null}
      <View
        style={[
          styles.inputRow,
          {
            borderColor,
            height: multiline ? undefined : inputHeight,
            minHeight: multiline ? inputHeight : undefined,
            backgroundColor: isDark ? '#1F2937' : '#FFFFFF',
          },
          focused && styles.inputFocused,
          !editable && [styles.inputDisabled, { backgroundColor: isDark ? '#374151' : '#F3F4F6' }],
        ]}
      >
        <TextInput
          style={[
            styles.input,
            { color: colors.text },
            multiline && { textAlignVertical: 'top', paddingTop: 12 },
          ]}
          placeholder={placeholder}
          placeholderTextColor={isDark ? '#6B7280' : '#9CA3AF'}
          value={value}
          onChangeText={onChangeText}
          secureTextEntry={secureTextEntry}
          multiline={multiline}
          numberOfLines={multiline ? numberOfLines : undefined}
          onFocus={() => setFocused(true)}
          onBlur={(e) => {
            setFocused(false);
            if (onBlur) onBlur(e);
          }}
          autoCapitalize="none"
          autoCorrect={false}
          editable={editable}
          {...rest}
        />
      </View>
      {error ? <Text style={styles.errorText}>{error}</Text> : null}
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    marginBottom: 16,
  },
  labelRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: 6,
  },
  label: {
    fontSize: 13,
    fontWeight: '600',
    color: '#374151',
    flexShrink: 1,
  },
  inputRow: {
    flexDirection: 'row',
    alignItems: 'center',
    borderWidth: 1,
    borderRadius: 10,
    backgroundColor: '#FFFFFF',
    paddingHorizontal: 14,
  },
  inputFocused: {},
  inputDisabled: {
    backgroundColor: '#F3F4F6',
  },
  input: {
    flex: 1,
    fontSize: 15,
    color: '#111827',
    paddingVertical: 0,
  },
  rightElement: {
    marginLeft: 8,
  },
  errorText: {
    fontSize: 12,
    color: '#EF4444',
    marginTop: 4,
  },
});
