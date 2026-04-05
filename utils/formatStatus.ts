// Elly Mobile App — status formatting utilities
// Maps raw API status strings to UI badge variants and display labels.

type BadgeVariant = 'success' | 'warning' | 'error' | 'info' | 'neutral';

const STATUS_COLOR_MAP: Record<string, BadgeVariant> = {
  // Publication states
  published: 'success',
  active: 'success',
  enabled: 'success',
  live: 'success',

  draft: 'warning',
  pending: 'warning',
  scheduled: 'info',
  review: 'info',
  'in-review': 'info',

  archived: 'neutral',
  inactive: 'neutral',
  disabled: 'neutral',
  hidden: 'neutral',

  deleted: 'error',
  rejected: 'error',
  failed: 'error',
  error: 'error',
};

const STATUS_LABEL_MAP: Record<string, string> = {
  published: 'Published',
  active: 'Active',
  enabled: 'Enabled',
  live: 'Live',

  draft: 'Draft',
  pending: 'Pending',
  scheduled: 'Scheduled',
  review: 'In Review',
  'in-review': 'In Review',

  archived: 'Archived',
  inactive: 'Inactive',
  disabled: 'Disabled',
  hidden: 'Hidden',

  deleted: 'Deleted',
  rejected: 'Rejected',
  failed: 'Failed',
  error: 'Error',
};

/**
 * Returns the badge variant for a given status string.
 * Falls back to 'neutral' for unknown statuses.
 */
export function getStatusColor(status: string): BadgeVariant {
  const normalised = status.toLowerCase().trim();
  return STATUS_COLOR_MAP[normalised] ?? 'neutral';
}

/**
 * Returns a human-readable display label for a given status string.
 * Falls back to title-cased input for unknown statuses.
 */
export function getStatusLabel(status: string): string {
  const normalised = status.toLowerCase().trim();
  return (
    STATUS_LABEL_MAP[normalised] ??
    status.charAt(0).toUpperCase() + status.slice(1)
  );
}

/**
 * Maps a boolean active/inactive flag to a badge label and variant.
 * Useful for API fields that use boolean rather than string status.
 */
export function formatBooleanStatus(status: boolean): { label: string; variant: 'success' | 'neutral' } {
  return status
    ? { label: 'Aktif', variant: 'success' }
    : { label: 'Pasif', variant: 'neutral' };
}
