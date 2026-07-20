// App.tsx — the app shell. NotificationBell is never imported here — that's the
// seeded defect. See SEEDED_DEFECT.md.

export function App() {
  return (
    <div className="app">
      <header>
        <h1>Dashboard</h1>
        {/* NotificationBell should render here per intent.md, but it doesn't. */}
      </header>
      <main>{/* ... */}</main>
    </div>
  );
}
