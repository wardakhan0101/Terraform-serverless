import React, { useEffect, useState, type FormEvent } from 'react';
import { createRoot } from 'react-dom/client';
import type { CognitoUser } from 'amazon-cognito-identity-js';
import { request, dateLabel, ratingLabel, type Book, type Review, type Ranking, type Page, type Config, type Role } from './api';
import * as auth from './auth';
import * as sample from './demo';
import './style.css';

const demo = new URLSearchParams(location.search).get('demo') === '1';
type Session = { user: CognitoUser; role: Role; email: string };
function App() {
  const [config, setConfig] = useState<Config | null>(null);
  const [setup, setSetup] = useState(false);
  const [page, setPage] = useState<'discover' | 'library'>('discover');
  const [books, setBooks] = useState<Book[]>([]);
  const [rankings, setRankings] = useState<Ranking[]>([]);
  const [cursor, setCursor] = useState<string | null>(null);
  const [selected, setSelected] = useState<Book | null>(null);
  const [reviews, setReviews] = useState<Review[]>([]);
  const [reviewCursor, setReviewCursor] = useState<string | null>(null);
  const [session, setSession] = useState<Session | null>(null);
  const [modal, setModal] = useState<'auth' | 'book' | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [notice, setNotice] = useState('');
  const [search, setSearch] = useState('');
  const [reviewRating, setReviewRating] = useState(5);

  useEffect(() => {
    if (demo) { setBooks(sample.books); setRankings(sample.rankings); return; }
    fetch('/config.json', { cache: 'no-store' }).then(r => { if (!r.ok) throw Error(); return r.json(); })
      .then(c => { if (!c.pools?.author?.clientId || !c.pools?.reader?.clientId) throw Error(); setConfig(c); })
      .catch(() => setSetup(true));
  }, []);

  async function load(next?: string) {
    if (demo || !config) return;
    setBusy(true); setError('');
    try {
      if (page === 'discover') {
        const ranking = await request<{ items: Ranking[] }>(config, '/discover');
        const details = await Promise.all(ranking.items.map(item => request<Book>(config, `/books/${item.bookId}`)));
        setRankings(ranking.items); setBooks(details); setCursor(null);
      } else {
        const result = await request<Page<Book>>(config, `/books${next ? '?cursor=' + encodeURIComponent(next) : ''}`);
        setBooks(previous => next ? [...previous, ...result.items] : result.items); setCursor(result.nextCursor);
      }
    } catch (e) { setError((e as Error).message); } finally { setBusy(false); }
  }
  useEffect(() => { setSearch(''); setSelected(null); void load(); }, [config, page]);

  async function openBook(book: Book, next?: string) {
    setSelected(book); setError(''); setNotice('');
    if (demo) { setReviews(sample.reviews.filter(r => r.bookId === book.bookId)); return; }
    if (!config) return;
    setBusy(true);
    try {
      const result = await request<Page<Review>>(config, `/reviews/${book.bookId}${next ? '?cursor=' + encodeURIComponent(next) : ''}`);
      setReviews(previous => next ? [...previous, ...result.items] : result.items); setReviewCursor(result.nextCursor);
    } catch (e) { setError((e as Error).message); } finally { setBusy(false); }
  }

  async function write(path: string, body: unknown) {
    if (!config || !session || demo) throw new Error('Sign in to continue.');
    return request<Book | Review>(config, path, { method: 'POST', headers: {
      'Content-Type': 'application/json', Authorization: await auth.getToken(session.user),
    }, body: JSON.stringify(body) });
  }
  async function submitReview(event: FormEvent<HTMLFormElement>) {
    event.preventDefault(); if (!selected) return;
    const form = event.currentTarget; const data = new FormData(form); setBusy(true); setError('');
    try {
      const review = await write(`/reviews/${selected.bookId}`, { rating: reviewRating, text: data.get('text') || '' }) as Review;
      setReviews(old => [review, ...old]); form.reset();
      setNotice('Your review is published. Discover ratings will update shortly. Reviews cannot be changed.');
    } catch (e) { setError((e as Error).message); } finally { setBusy(false); }
  }
  async function submitBook(event: FormEvent<HTMLFormElement>) {
    event.preventDefault(); const form = event.currentTarget; const data = new FormData(form); setBusy(true); setError('');
    try {
      const book = await write('/books', Object.fromEntries(data)) as Book;
      setModal(null); setSelected(book); setReviews([]); setReviewCursor(null);
      setNotice('Your book is published. Book details cannot be changed.');
    } catch (e) { setError((e as Error).message); } finally { setBusy(false); }
  }
  const visible = books.filter(b => `${b.title} ${b.author}`.toLowerCase().includes(search.toLowerCase()));
  return <>
    {demo && <div className="demo-banner">Local preview · Sample books and reviews · Sign-up and publishing are disabled <a href="/">Exit preview</a></div>}
    <header className="header"><a className="brand" href="#" onClick={e => { e.preventDefault(); setSelected(null); setPage('discover'); }}><span className="brand-mark">m.</span> marginalia<span className="brand-dot">.</span></a>
      <nav aria-label="Main navigation"><button className={!selected && page === 'discover' ? 'nav active' : 'nav'} onClick={() => { setSelected(null); setPage('discover'); }}>Discover</button><button className={!selected && page === 'library' ? 'nav active' : 'nav'} onClick={() => { setSelected(null); setPage('library'); }}>The library</button></nav>
      <div className="account">{session ? <><span className="role-label">{session.role}</span><button className="quiet" onClick={() => { session.user.signOut(); setSession(null); }}>Sign out</button></> : <button className="quiet" onClick={() => setModal('auth')} disabled={demo || setup}>Sign in <span aria-hidden="true">↗</span></button>}<button className="primary small" disabled={demo || setup} onClick={() => setModal(session?.role === 'author' ? 'book' : 'auth')}>Share your book <span aria-hidden="true">＋</span></button></div>
    </header>
    <main>
      {setup ? <section className="setup"><p className="eyebrow">READY WHEN YOU ARE</p><h1>Your next chapter starts here.</h1><p>The application is built locally. AWS endpoints and account signup become available only after a future deployment.</p><a className="primary" href="/?demo=1">Explore the local preview →</a></section> : selected ? <>
        <button className="back" onClick={() => { setSelected(null); setError(''); setNotice(''); }}>← Back to {page === 'discover' ? 'Discover' : 'the library'}</button>
        <section className="book-detail"><div><p className="eyebrow">FROM THE LIBRARY</p><h1>{selected.title}</h1><p className="author">by {selected.author}</p><p className="description">{selected.description}</p><p className="muted">Added {dateLabel(selected.createdAt)}</p></div><aside className="reading-note"><span className="large-quote">“</span><h3>Every book starts a conversation.</h3><p>Read thoughtfully.<br />Review honestly.</p></aside></section>
        <section className="reviews"><div className="section-heading"><h2>Reader reviews</h2><span className="muted">Newest first</span></div>
          {reviews.map(r => <article className="review" key={r.reviewId}><div><span className="stars" aria-label={ratingLabel(r.rating)}>{'★'.repeat(r.rating)}<span className="empty-stars">{'★'.repeat(5 - r.rating)}</span></span><time>{dateLabel(r.createdAt)}</time></div><p>{r.text || 'A rating without a written review.'}</p></article>)}
          {!reviews.length && !busy && <p className="empty">No reviews yet. Be the first to share a perspective.</p>}
          {reviewCursor && <button className="secondary" onClick={() => void openBook(selected, reviewCursor)} disabled={busy}>More reviews</button>}
          {session?.role === 'reader' && !demo ? <form className="review-form" onSubmit={submitReview}><h3>Your perspective matters.</h3><label>Your rating <select value={reviewRating} onChange={e => setReviewRating(Number(e.target.value))}>{[5, 4, 3, 2, 1].map(v => <option key={v} value={v}>{v} star{v > 1 ? 's' : ''}</option>)}</select></label><label>Your review <span className="muted">(optional)</span><textarea name="text" maxLength={2000} rows={4} placeholder="What stayed with you?" /></label><p className="muted">One review per book. Once published, your rating and words cannot be edited or deleted.</p><button className="primary" disabled={busy}>Publish review →</button></form> : <p className="muted">{demo ? 'Reviews are read-only in the local preview.' : 'Sign in with a reader account to leave a review.'}</p>}
        </section>
      </> : <>
        <section className="hero"><div><p className="eyebrow">A LITTLE CURIOSITY. A GREAT NEXT READ.</p><h1>Good books.<br /><em>Honest words.</em></h1><p className="hero-copy">Find your next favorite through the readers who found it first. Independent stories, shared perspectives.</p><button className="text-link" onClick={() => { setPage('library'); document.getElementById('shelf')?.scrollIntoView({ behavior: 'smooth' }); }}>Explore the library <span aria-hidden="true">↗</span></button></div><div className="hero-art" aria-hidden="true"><div className="orbit"></div><div className="paper paper-back"></div><div className="paper paper-front"><span>THE READER'S<br />COMMONPLACE</span><i>Stories<br />stay<br />with us.</i><small>TURN A PAGE. FIND A PERSPECTIVE.</small></div><div className="seal">READ<br />REFLECT<br />REPEAT</div><span className="spark">✳</span></div></section>
        <div className="editorial-strip"><span>Made for the margins</span><p>No cover to judge. Just stories worth discovering.</p><span aria-hidden="true">✦</span></div>
        <section id="shelf" className="shelf"><div className="section-heading"><div><p className="eyebrow">{page === 'discover' ? 'THE COMMUNITY SHELF' : 'INDEPENDENT VOICES'}</p><h2>{page === 'discover' ? 'Loved by readers' : 'Browse the library'}</h2></div>{page === 'discover' ? <span className="sort-label">Top rated <span aria-hidden="true">↓</span></span> : <label className="search-label"><span className="sr-only">Search loaded books</span><input type="search" placeholder="Search these books…" value={search} onChange={e => setSearch(e.target.value)} /></label>}</div>
          <div className="book-grid">{visible.map((book, index) => { const rank = rankings.find(r => r.bookId === book.bookId); return <button className="book-card" key={book.bookId} onClick={() => void openBook(book)}><div className="card-top"><span className="book-number">{String(index + 1).padStart(2, '0')}</span><span className="card-arrow" aria-hidden="true">↗</span></div><h3>{book.title}</h3><p className="card-author">{book.author}</p><p className="card-description">{book.description}</p><div className="card-bottom">{rank ? <><span><span className="stars" aria-hidden="true">★</span> <strong>{rank.averageRating.toFixed(1)}</strong><span className="muted"> / 5</span></span><span className="muted">{rank.reviewCount} reviews</span></> : <span className="muted">Discover a new voice</span>}</div></button>; })}</div>
          {!books.length && !busy && !error && <div className="empty"><h3>{page === 'discover' ? 'The next favorite could be yours.' : 'The shelf is waiting.'}</h3><p>{page === 'discover' ? 'Books appear here after their first reader rating.' : 'Authors can add the first book.'}</p></div>}
          {cursor && <button className="secondary load-more" disabled={busy} onClick={() => void load(cursor)}>Load more books</button>}
          <p className="shelf-note">{page === 'discover' ? 'Ranked by average reader rating. Ratings refresh periodically.' : 'Every book has a story. All entries are permanent.'}</p>
        </section><section className="invitation"><div><p className="eyebrow">FOR THE STORYTELLERS</p><h2>Your words belong here.</h2><p>Give your book a place on the shelf. Let readers do the rest.</p></div><button className="primary" disabled={demo || setup} onClick={() => setModal(session?.role === 'author' ? 'book' : 'auth')}>Join as an author ↗</button></section>
      </>}
      {busy && <p className="status" role="status">Turning the page…</p>}
      {error && <div className="message error" role="alert">{error}<button className="quiet" onClick={() => setError('')}>Dismiss</button></div>}
      {notice && <p className="message success" role="status">{notice}</p>}
    </main>
    <footer><span className="footer-brand">marginalia.</span><p>A home for books. A place for perspectives.</p><span>Read something good.</span></footer>
    {modal && <dialog open className="modal" aria-label={modal === 'auth' ? 'Account access' : 'Add a book'} onCancel={() => setModal(null)}><div className="modal-inner"><button className="modal-close" aria-label="Close dialog" onClick={() => setModal(null)}>×</button>{modal === 'auth' ? config && <AuthForm config={config} onSuccess={value => { setSession(value); setModal(null); setError(''); }} /> : <form onSubmit={submitBook}><p className="eyebrow">ADD TO THE LIBRARY</p><h2>A new chapter.</h2><label>Book title<input name="title" required maxLength={200} /></label><label>Author name<input name="author" required maxLength={120} /></label><label>Description<textarea name="description" required maxLength={5000} rows={5} /></label><p className="muted">Metadata only. Please check carefully: books cannot be edited or deleted.</p>{error && <p className="error" role="alert">{error}</p>}<button className="primary" disabled={busy}>Publish book →</button></form>}</div></dialog>}
  </>;
}

function AuthForm({ config, onSuccess }: { config: Config; onSuccess: (session: Session) => void }) {
  const [role, setRole] = useState<Role>('reader');
  const [mode, setMode] = useState<'signin' | 'signup' | 'confirm'>('signin');
  const [email, setEmail] = useState('');
  const [error, setError] = useState('');
  const [info, setInfo] = useState('');
  const [busy, setBusy] = useState(false);
  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault(); const data = new FormData(event.currentTarget); setBusy(true); setError('');
    try {
      if (mode === 'signup') { await auth.signUp(config, role, email, String(data.get('password'))); setMode('confirm'); setInfo('Check your email for a confirmation code.'); }
      else if (mode === 'confirm') { await auth.confirm(config, role, email, String(data.get('code'))); setMode('signin'); setInfo('Email confirmed. You can now sign in.'); }
      else { const user = await auth.signIn(config, role, email, String(data.get('password'))); onSuccess({ user, role, email }); }
    } catch (e) { setError((e as Error).message); } finally { setBusy(false); }
  }
  return <form onSubmit={submit}><p className="eyebrow">FIND YOUR PLACE</p><h2>{mode === 'signup' ? 'Join the conversation.' : mode === 'confirm' ? 'One last step.' : 'Welcome back.'}</h2><div className="role-switch" aria-label="Account type">{(['reader', 'author'] as Role[]).map(r => <button key={r} type="button" disabled={mode === 'confirm'} className={role === r ? 'selected' : ''} onClick={() => setRole(r)}>{r === 'reader' ? 'Reader' : 'Author'}</button>)}</div><p className="muted">{role === 'reader' ? 'Readers rate books and share reviews.' : 'Authors add their books to the library.'} Accounts are separate.</p><label>Email address<input type="email" required autoComplete="email" value={email} onChange={e => setEmail(e.target.value)} readOnly={mode === 'confirm'} /></label>{mode === 'confirm' ? <label>Confirmation code<input name="code" inputMode="numeric" required autoComplete="one-time-code" /></label> : <label>Password<input type="password" name="password" required minLength={mode === 'signup' ? 12 : 1} autoComplete={mode === 'signup' ? 'new-password' : 'current-password'} /></label>}{mode === 'signup' && <p className="muted">Use at least 12 characters including uppercase, lowercase, a number and a symbol.</p>}{error && <p className="error" role="alert">{error}</p>}{info && <p role="status">{info}</p>}<button className="primary" disabled={busy}>{busy ? 'Please wait…' : mode === 'signup' ? 'Create account →' : mode === 'confirm' ? 'Confirm email →' : 'Sign in →'}</button>{mode !== 'confirm' && <button className="text-link auth-toggle" type="button" onClick={() => { setMode(mode === 'signin' ? 'signup' : 'signin'); setError(''); }}>{mode === 'signin' ? 'New here? Create an account' : 'Already a member? Sign in'}</button>}</form>;
}

createRoot(document.getElementById('root')!).render(<React.StrictMode><App /></React.StrictMode>);
