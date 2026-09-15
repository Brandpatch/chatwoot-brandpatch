import { hasPushPermissions } from 'dashboard/helper/pushHelper';

// One banner per ringing call, keyed by its SID, so a re-render never stacks
// duplicates and a call that stops ringing takes its banner down with it: a
// notification for a call that already ended is worse than no notification.
const openNotifications = new Map();

const open = call => {
  // An agent looking at the tab already has the widget and the ringtone. The
  // banner exists for the one who is in another application, which is the case
  // the report is about, so focus is what decides whether it is worth raising.
  if (document.hasFocus()) return;

  let notification;

  try {
    notification = new Notification(call.title, {
      body: call.body,
      tag: `voice-call-${call.callSid}`,
      // Chrome leaves it on screen until the agent acts on it, which is the
      // whole point: one that fades after a few seconds is the one they miss.
      // Other browsers ignore the flag.
      requireInteraction: true,
    });
  } catch {
    // Some browsers only allow notifications raised from a service worker.
    // Losing the banner is acceptable — the widget and the ringtone still
    // surface the call — but it must not take the ring down with it.
    return;
  }

  notification.onclick = () => {
    // The widget floats over every screen of the dashboard, so bringing the
    // window forward is enough to put the answer button under their cursor.
    window.focus();
    notification.close();
  };

  openNotifications.set(call.callSid, notification);
};

// Declares which calls should have a banner on screen right now; opening and
// closing follows from the difference. Safe to call repeatedly.
export const syncIncomingCallNotifications = (calls = []) => {
  const live = new Map(calls.map(call => [call.callSid, call]));

  openNotifications.forEach((notification, callSid) => {
    if (live.has(callSid)) return;

    notification.close();
    openNotifications.delete(callSid);
  });

  if (!hasPushPermissions()) return;

  live.forEach((call, callSid) => {
    if (openNotifications.has(callSid)) return;

    open(call);
  });
};
