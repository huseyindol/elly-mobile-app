export function getTypeColor(typeStr: string | undefined): string {
  if (!typeStr) return '#9CA3AF'; // default gray

  const type = typeStr.toUpperCase();

  switch (type) {
    case 'PAGE':
    case 'PAGES':
      return '#4F46E5'; // indigo
    case 'POST':
    case 'POSTS':
    case 'ARTICLE': // in case they use this
      return '#059669'; // emerald
    case 'BANNER':
    case 'BANNERS':
      return '#D97706'; // amber
    case 'COMPONENT':
    case 'COMPONENTS':
      return '#7C3AED'; // purple
    case 'WIDGET':
    case 'WIDGETS':
      return '#DB2777'; // pink
    case 'ASSET':
    case 'ASSETS':
      return '#0EA5E9'; // sky
    case 'FORM':
    case 'FORMS':
      return '#8B5CF6'; // violet
    case 'CONTENT':
    case 'CONTENTS':
      return '#F97316'; // orange
    default:
      return '#9CA3AF'; // neutral fallback
  }
}
