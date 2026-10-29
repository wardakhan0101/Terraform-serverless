import { describe, expect, it, vi } from 'vitest';
import { ratingLabel, request, type Config } from './api';

describe('API boundary', () => {
  it('uses readable rating labels', () => expect(ratingLabel(4.25)).toBe('4.3 out of 5 stars'));
  it('surfaces duplicate-review failures without pretending success', async () => {
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue({ ok: false, json: async () => ({ detail: 'You have already reviewed this book' }) }));
    await expect(request({ apiBase: '' } as Config, '/reviews/book', { method: 'POST' })).rejects.toThrow('already reviewed');
    vi.unstubAllGlobals();
  });
});
