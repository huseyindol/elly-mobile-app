import { TouchableOpacity, Text, ActivityIndicator, StyleSheet } from 'react-native';

interface AiFieldButtonProps {
  onClick: () => void;
  isLoading: boolean;
  disabled?: boolean;
  label?: string;
}

export function AiFieldButton({
  onClick,
  isLoading,
  disabled = false,
  label = 'AI ile oluştur',
}: AiFieldButtonProps) {
  return (
    <TouchableOpacity
      style={[styles.button, disabled && styles.disabledButton]}
      onPress={onClick}
      disabled={disabled || isLoading}
      activeOpacity={0.7}
    >
      {isLoading ? (
        <ActivityIndicator size="small" color="#6366F1" style={styles.spinner} />
      ) : (
        <Text style={[styles.icon, disabled && styles.disabledText]}>✨</Text>
      )}
      <Text style={[styles.text, disabled && styles.disabledText]}>{label}</Text>
    </TouchableOpacity>
  );
}

const styles = StyleSheet.create({
  button: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: '#EEF2FF',
    paddingHorizontal: 8,
    paddingVertical: 4,
    borderRadius: 6,
    marginLeft: 8,
    borderWidth: 1,
    borderColor: '#C7D2FE',
  },
  disabledButton: {
    backgroundColor: '#F3F4F6',
    borderColor: '#E5E7EB',
    opacity: 0.6,
  },
  icon: {
    fontSize: 12,
    marginRight: 4,
  },
  text: {
    fontSize: 12,
    fontWeight: '600',
    color: '#4F46E5',
  },
  disabledText: {
    color: '#9CA3AF',
  },
  spinner: {
    marginRight: 4,
    transform: [{ scale: 0.6 }],
  },
});
