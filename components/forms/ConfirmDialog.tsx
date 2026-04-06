// Elly Mobile App — ConfirmDialog utility
// Wraps React Native Alert for consistent destructive-action confirmation dialogs.

import { Alert } from 'react-native';

interface ConfirmDialogOptions {
  title?: string;
  message?: string;
  confirmLabel?: string;
  onConfirm: () => void;
}

export function showConfirmDialog({
  title = 'Silmek istediğinize emin misiniz?',
  message = 'Bu işlem geri alınamaz.',
  confirmLabel = 'Sil',
  onConfirm,
}: ConfirmDialogOptions) {
  Alert.alert(title, message, [
    { text: 'İptal', style: 'cancel' },
    { text: confirmLabel, style: 'destructive', onPress: onConfirm },
  ]);
}
