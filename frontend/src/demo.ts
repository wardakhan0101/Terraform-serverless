import type { Book, Ranking, Review } from './api';

export const books: Book[] = [
  { bookId: '11111111-1111-4111-8111-111111111111', title: 'The Art of Paying Attention', author: 'Elena Hart', description: 'An invitation to notice the extraordinary hiding inside ordinary days. A thoughtful collection of essays on slowing down, looking closely, and finding meaning in the world around us.', createdAt: '2026-10-20T10:00:00Z' },
  { bookId: '22222222-2222-4222-8222-222222222222', title: 'A Map of Small Things', author: 'Samir Ali', description: 'When a cartographer returns to his childhood town, he begins mapping the places that never appear on a map: a first friendship, an unfinished conversation, a home that no longer exists.', createdAt: '2026-10-18T10:00:00Z' },
  { bookId: '33333333-3333-4333-8333-333333333333', title: 'Between the Lines', author: 'Maya Brooks', description: 'Two strangers exchange notes in the margins of a secondhand book. What begins as a literary disagreement becomes a quiet exploration of connection, memory, and the stories we tell ourselves.', createdAt: '2026-10-16T10:00:00Z' },
  { bookId: '44444444-4444-4444-8444-444444444444', title: 'The Long Way Home', author: 'James Okafor', description: 'A moving story of belonging across generations. Three siblings follow the same road home, each carrying a different version of the past.', createdAt: '2026-10-14T10:00:00Z' },
];
export const rankings: Ranking[] = books.map((book, i) => ({ bookId: book.bookId, averageRating: [4.8, 4.7, 4.6, 4.4][i], reviewCount: [24, 18, 31, 12][i] }));
export const reviews: Review[] = [{ reviewId: 'sample', bookId: books[0].bookId, rating: 5, text: 'The kind of book that makes you close the last page and look at the world a little differently.', createdAt: '2026-10-23T12:00:00Z' }];
