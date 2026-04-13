import React, { useRef, useState, useEffect, useMemo } from 'react';
import { View, Text, StyleSheet } from 'react-native';
import { RichEditor, RichToolbar, actions } from 'react-native-pell-rich-editor';

export interface RichTextEditorProps {
  label?: string;
  value: string;
  onChange: (html: string) => void;
  error?: string;
  rightElement?: React.ReactNode;
}

export function RichTextEditor({
  label,
  value,
  onChange,
  error,
  rightElement,
}: RichTextEditorProps) {
  const richText = useRef<RichEditor>(null);
  const [focused, setFocused] = useState(false);
  const [internalValue, setInternalValue] = useState(value || '');

  // Dışarıdan gelen değişiklikleri yakalamak (Örn: AI paneli ile text değişirse)
  useEffect(() => {
    if (value !== internalValue) {
      richText.current?.setContentHTML(value || '');
      setInternalValue(value || '');
    }
  }, [value, internalValue]);

  const handleChange = (html: string) => {
    setInternalValue(html);
    onChange(html);
  };

  const borderColor = error ? '#EF4444' : focused ? '#4F46E5' : '#D1D5DB';

  const iconMap = useMemo(
    () => ({
      [actions.heading1]: () => <Text style={styles.toolbarIcon}>H1</Text>,
      [actions.heading2]: () => <Text style={styles.toolbarIcon}>H2</Text>,
    }),
    []
  );

  return (
    <View style={styles.container}>
      {label || rightElement ? (
        <View style={styles.labelRow}>
          {label ? <Text style={styles.label}>{label}</Text> : <View style={{ flex: 1 }} />}
          {rightElement ? <View style={styles.rightElement}>{rightElement}</View> : null}
        </View>
      ) : null}

      <View style={[styles.editorContainer, { borderColor }]}>
        <RichToolbar
          editor={richText}
          actions={[
            actions.setBold,
            actions.setItalic,
            actions.setUnderline,
            actions.heading1,
            actions.heading2,
            actions.insertBulletsList,
            actions.insertOrderedList,
          ]}
          iconMap={iconMap}
          style={styles.toolbar}
          selectedButtonStyle={{ backgroundColor: '#EEF2FF', borderRadius: 4 }}
          iconTint="#6B7280"
          selectedIconTint="#4F46E5"
        />

        <RichEditor
          ref={richText}
          initialContentHTML={value}
          onChange={handleChange}
          onFocus={() => setFocused(true)}
          onBlur={() => setFocused(false)}
          placeholder="İçeriğinizi buraya yazın..."
          initialHeight={250}
          useContainer={true}
          containerStyle={styles.richEditor}
          editorStyle={{
            backgroundColor: '#FFFFFF',
            color: '#111827',
            placeholderColor: '#9CA3AF',
          }}
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
  rightElement: {
    marginLeft: 8,
  },
  editorContainer: {
    borderWidth: 1,
    borderRadius: 10,
    backgroundColor: '#FFFFFF',
    overflow: 'hidden',
  },
  toolbar: {
    backgroundColor: '#F9FAFB',
    borderBottomWidth: 1,
    borderBottomColor: '#E5E7EB',
  },
  toolbarIcon: {
    fontSize: 14,
    fontWeight: '700',
    color: '#6B7280',
  },
  richEditor: {
    borderBottomLeftRadius: 10,
    borderBottomRightRadius: 10,
  },
  errorText: {
    fontSize: 12,
    color: '#EF4444',
    marginTop: 4,
  },
});
