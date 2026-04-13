import React, { useRef } from 'react';
import { StyleSheet, View, Text, TouchableOpacity, Animated, Alert } from 'react-native';
import Swipeable from 'react-native-gesture-handler/Swipeable';
import { Ionicons } from '@expo/vector-icons';
import { useThemeColor } from '../../hooks/useThemeColor';

interface SwipeableListItemProps {
  children: React.ReactNode;
  onView: () => void;
  onDelete: () => void;
}

export function SwipeableListItem({ children, onView, onDelete }: SwipeableListItemProps) {
  const swipeableRef = useRef<Swipeable>(null);
  const { colors } = useThemeColor();

  const confirmDelete = () => {
    swipeableRef.current?.close();
    Alert.alert('Silme İşlemi', 'Bu öğeyi silmek istediğinize emin misiniz?', [
      { text: 'İptal', style: 'cancel' },
      { text: 'Sil', style: 'destructive', onPress: onDelete },
    ]);
  };

  const handleView = () => {
    swipeableRef.current?.close();
    onView();
  };

  const renderRightActions = (
    _progress: Animated.AnimatedInterpolation<number>,
    dragX: Animated.AnimatedInterpolation<number>
  ) => {
    const scale = dragX.interpolate({
      inputRange: [-100, 0],
      outputRange: [1, 0],
      extrapolate: 'clamp',
    });

    return (
      <View style={styles.actionsContainer}>
        <TouchableOpacity style={[styles.actionButton, styles.viewAction]} onPress={handleView}>
          <Animated.View style={{ transform: [{ scale }], alignItems: 'center' }}>
            <Ionicons name="eye-outline" size={24} color="#FFF" />
            <Text style={styles.actionText}>İncele</Text>
          </Animated.View>
        </TouchableOpacity>
        <TouchableOpacity
          style={[styles.actionButton, styles.deleteAction]}
          onPress={confirmDelete}
        >
          <Animated.View style={{ transform: [{ scale }], alignItems: 'center' }}>
            <Ionicons name="trash-outline" size={24} color="#FFF" />
            <Text style={styles.actionText}>Sil</Text>
          </Animated.View>
        </TouchableOpacity>
      </View>
    );
  };

  return (
    <Swipeable
      ref={swipeableRef}
      renderRightActions={renderRightActions}
      rightThreshold={120} // Full swipe threshold to trigger the auto-open? ReanimatedSwipeable might not natively support it easily without hooks, but we'll use standard threshold.
      onSwipeableWillOpen={(direction) => {
        // Unfortunately standard react-native-gesture-handler does not natively distinguish fully swiping to trigger vs just opening.
        // We leave the visual swipe open. If we want we could dispatch `handleView()` here based on a threshold calculation, but opening it is visually correct first.
      }}
      containerStyle={[styles.containerStyle, { backgroundColor: colors.surface }]}
      friction={2}
    >
      {children}
    </Swipeable>
  );
}

const styles = StyleSheet.create({
  containerStyle: {
    marginBottom: 10,
    borderRadius: 12,
    overflow: 'hidden',
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 1 },
    shadowOpacity: 0.06,
    shadowRadius: 4,
    elevation: 2,
  },
  actionsContainer: {
    flexDirection: 'row',
    width: 140, // 70px per button
  },
  actionButton: {
    width: 70,
    justifyContent: 'center',
    alignItems: 'center',
  },
  viewAction: {
    backgroundColor: '#4F46E5',
  },
  deleteAction: {
    backgroundColor: '#EF4444',
  },
  actionText: {
    color: '#FFF',
    fontSize: 12,
    marginTop: 4,
    fontWeight: '600',
  },
});
