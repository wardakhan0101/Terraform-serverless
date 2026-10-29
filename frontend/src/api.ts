export type Role = 'author' | 'reader';
export interface Config { region: string; apiBase: string; pools: Record<Role, { poolId: string; clientId: string }> }
export interface Book { bookId: string; title: string; author: string; description: string; createdAt: string }
export interface Review { reviewId: string; bookId: string; rating: number; text: string; createdAt: string }
export interface Ranking { bookId: string; averageRating: number; reviewCount: number }
export interface Page<T> { items: T[]; nextCursor: string | null }

export async function request<T>(config: Config, path: string, options: RequestInit = {}): Promise<T> {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 15000);
  try {
    const response = await fetch(config.apiBase + path, { ...options, signal: controller.signal });
    const body = await response.json();
    if (!response.ok) {
      const detail = typeof body.detail === 'string' ? body.detail : 'Please check the form and try again.';
      throw new Error(detail || body.message || 'The request could not be completed.');
    }
    return body as T;
  } catch (error) {
    if (error instanceof DOMException && error.name === 'AbortError') throw new Error('The request timed out. Please try again.');
    throw error;
  } finally { clearTimeout(timeout); }
}

export function ratingLabel(rating: number) { return `${rating.toFixed(1)} out of 5 stars`; }
export function dateLabel(date: string) { return new Intl.DateTimeFormat('en', { month: 'short', day: 'numeric', year: 'numeric' }).format(new Date(date)); }
