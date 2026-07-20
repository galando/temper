// NotificationBell.tsx — a fully-implemented notification bell component.
//
// SEEDED DEFECT (do not fix without updating evals/fixtures/notifications/SEEDED_DEFECT.md):
// this component is complete and correct in isolation, but it is never imported or
// rendered anywhere in src/App.tsx — see that file. The feature "works" (compiles,
// has no bugs of its own) but is unreachable by any user. This is the "missing wiring"
// failure pattern: code correct, integration missing.

import { useState, useEffect } from 'react';

interface Notification {
  id: string;
  message: string;
  read: boolean;
}

export function NotificationBell({ notifications }: { notifications: Notification[] }) {
  const [unreadCount, setUnreadCount] = useState(0);

  useEffect(() => {
    setUnreadCount(notifications.filter((n) => !n.read).length);
  }, [notifications]);

  return (
    <button aria-label="Notifications" data-testid="notification-bell">
      🔔 {unreadCount > 0 ? unreadCount : null}
    </button>
  );
}
