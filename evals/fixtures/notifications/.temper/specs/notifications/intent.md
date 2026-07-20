# Intent: Notification Bell

## Problem
Users have no way to see unread notifications while using the dashboard.

## Success Criteria
- A notification bell is visible in the dashboard header showing the unread count
- The bell updates when new notifications arrive

## Scenarios

Scenario: Unread count shown in the header
  Given a user has 3 unread notifications
  When they view the dashboard
  Then the notification bell in the header shows "3"

Scenario: Bell updates when a notification is marked read
  Given a user has 3 unread notifications
  When one is marked read
  Then the notification bell shows "2"
