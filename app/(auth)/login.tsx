// Login screen — tenant-only entry.
// Architectural decisions:
//   1. react-hook-form + zod validates username/email, password, and required tenantId.
//   2. loginType is fixed to 'tenant' in the schema and payload; no admin path on this screen.
//   3. The useLogin mutation from hooks/useAuth drives the API call; this screen
//      only handles the UI and delegates async state to React Query.

import { useState } from 'react';
import {
  View,
  Text,
  TextInput,
  TouchableOpacity,
  StyleSheet,
  ActivityIndicator,
  KeyboardAvoidingView,
  Platform,
  ScrollView,
  Alert,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useForm, Controller } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { z } from 'zod';
import { Ionicons } from '@expo/vector-icons';
import { useLogin } from '../../hooks/useAuth';

const loginSchema = z.object({
  usernameOrEmail: z.string().min(3, 'En az 3 karakter giriniz'),
  password: z.string().min(6, 'Şifre en az 6 karakter olmalıdır'),
  tenantId: z.string().min(1, 'Tenant ID zorunludur'),
  loginType: z.literal('tenant'),
});

type LoginFormData = z.infer<typeof loginSchema>;

export default function LoginScreen() {
  const [showPassword, setShowPassword] = useState(false);
  const { mutate: login, isPending } = useLogin();

  const {
    control,
    handleSubmit,
    formState: { errors },
  } = useForm<LoginFormData>({
    resolver: zodResolver(loginSchema),
    defaultValues: {
      usernameOrEmail: '',
      password: '',
      tenantId: '',
      loginType: 'tenant',
    },
  });

  const onSubmit = (data: LoginFormData) => {
    login(
      {
        usernameOrEmail: data.usernameOrEmail,
        password: data.password,
        tenantId: data.tenantId,
        loginType: 'tenant',
      },
      {
        onError: () => {
          Alert.alert('Giriş Başarısız', 'Kullanıcı adı, şifre veya tenant bilgileri hatalı.');
        },
      }
    );
  };

  return (
    <SafeAreaView style={styles.safe}>
      <KeyboardAvoidingView
        behavior={Platform.OS === 'ios' ? 'padding' : 'height'}
        style={styles.flex}
      >
        <ScrollView contentContainerStyle={styles.scroll} keyboardShouldPersistTaps="handled">
          {/* Header */}
          <View style={styles.header}>
            <View style={styles.logoCircle}>
              <Ionicons name="shield-checkmark" size={32} color="#4F46E5" />
            </View>
            <Text style={styles.title}>Elly Admin</Text>
            <Text style={styles.subtitle}>Hesabınıza giriş yapın</Text>
          </View>

          {/* Card */}
          <View style={styles.card}>
            {/* Username/Email */}
            <View style={styles.fieldGroup}>
              <Text style={styles.label}>E-posta veya kullanıcı adı</Text>
              <View style={[styles.inputRow, errors.usernameOrEmail && styles.inputError]}>
                <Ionicons name="mail-outline" size={18} color="#9CA3AF" style={styles.inputIcon} />
                <Controller
                  control={control}
                  name="usernameOrEmail"
                  render={({ field: { onChange, onBlur, value } }) => (
                    <TextInput
                      style={styles.input}
                      placeholder="E-posta veya kullanıcı adı"
                      placeholderTextColor="#9CA3AF"
                      autoCapitalize="none"
                      autoCorrect={false}
                      keyboardType="email-address"
                      onBlur={onBlur}
                      onChangeText={onChange}
                      value={value}
                      editable={!isPending}
                    />
                  )}
                />
              </View>
              {errors.usernameOrEmail && (
                <Text style={styles.errorText}>{errors.usernameOrEmail.message}</Text>
              )}
            </View>

            {/* Tenant ID */}
            <View style={styles.fieldGroup}>
              <Text style={styles.label}>Tenant ID</Text>
              <View style={[styles.inputRow, errors.tenantId && styles.inputError]}>
                <Ionicons
                  name="business-outline"
                  size={18}
                  color="#9CA3AF"
                  style={styles.inputIcon}
                />
                <Controller
                  control={control}
                  name="tenantId"
                  render={({ field: { onChange, onBlur, value } }) => (
                    <TextInput
                      style={styles.input}
                      placeholder="Tenant ID"
                      placeholderTextColor="#9CA3AF"
                      autoCapitalize="none"
                      autoCorrect={false}
                      onBlur={onBlur}
                      onChangeText={onChange}
                      value={value}
                      editable={!isPending}
                    />
                  )}
                />
              </View>
              {errors.tenantId && <Text style={styles.errorText}>{errors.tenantId.message}</Text>}
            </View>

            {/* Password */}
            <View style={styles.fieldGroup}>
              <Text style={styles.label}>Şifre</Text>
              <View style={[styles.inputRow, errors.password && styles.inputError]}>
                <Ionicons
                  name="lock-closed-outline"
                  size={18}
                  color="#9CA3AF"
                  style={styles.inputIcon}
                />
                <Controller
                  control={control}
                  name="password"
                  render={({ field: { onChange, onBlur, value } }) => (
                    <TextInput
                      style={styles.input}
                      placeholder="Şifrenizi giriniz"
                      placeholderTextColor="#9CA3AF"
                      secureTextEntry={!showPassword}
                      onBlur={onBlur}
                      onChangeText={onChange}
                      value={value}
                      editable={!isPending}
                    />
                  )}
                />
                <TouchableOpacity
                  onPress={() => setShowPassword(!showPassword)}
                  style={styles.eyeBtn}
                >
                  <Ionicons
                    name={showPassword ? 'eye-off-outline' : 'eye-outline'}
                    size={18}
                    color="#9CA3AF"
                  />
                </TouchableOpacity>
              </View>
              {errors.password && <Text style={styles.errorText}>{errors.password.message}</Text>}
            </View>

            {/* Submit */}
            <TouchableOpacity
              style={[styles.submitBtn, isPending && styles.submitBtnDisabled]}
              onPress={handleSubmit(onSubmit)}
              activeOpacity={0.85}
              disabled={isPending}
            >
              {isPending ? (
                <ActivityIndicator color="#fff" size="small" />
              ) : (
                <Text style={styles.submitText}>Giriş Yap</Text>
              )}
            </TouchableOpacity>
          </View>
        </ScrollView>
      </KeyboardAvoidingView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  safe: { flex: 1, backgroundColor: '#F9FAFB' },
  flex: { flex: 1 },
  scroll: { flexGrow: 1, justifyContent: 'center', padding: 24 },
  header: { alignItems: 'center', marginBottom: 32 },
  logoCircle: {
    width: 64,
    height: 64,
    borderRadius: 32,
    backgroundColor: '#EEF2FF',
    justifyContent: 'center',
    alignItems: 'center',
    marginBottom: 16,
  },
  title: { fontSize: 28, fontWeight: '700', color: '#111827', marginBottom: 4 },
  subtitle: { fontSize: 15, color: '#6B7280' },
  card: {
    backgroundColor: '#fff',
    borderRadius: 16,
    padding: 24,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.08,
    shadowRadius: 8,
    elevation: 3,
  },
  fieldGroup: { marginBottom: 16 },
  label: { fontSize: 13, fontWeight: '600', color: '#374151', marginBottom: 6 },
  inputRow: {
    flexDirection: 'row',
    alignItems: 'center',
    borderWidth: 1,
    borderColor: '#E5E7EB',
    borderRadius: 10,
    backgroundColor: '#F9FAFB',
    paddingHorizontal: 12,
  },
  inputError: { borderColor: '#EF4444' },
  inputIcon: { marginRight: 8 },
  input: { flex: 1, height: 48, fontSize: 15, color: '#111827' },
  eyeBtn: { padding: 4 },
  errorText: { fontSize: 12, color: '#EF4444', marginTop: 4 },
  submitBtn: {
    backgroundColor: '#4F46E5',
    borderRadius: 10,
    height: 50,
    justifyContent: 'center',
    alignItems: 'center',
    marginTop: 8,
  },
  submitBtnDisabled: { backgroundColor: '#A5B4FC' },
  submitText: { color: '#fff', fontSize: 16, fontWeight: '600' },
});
