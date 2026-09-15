const RINGTONE_URL = '/audio/dashboard/ringtone.mp3';

// The ringtone lives here rather than inside FloatingCallWidget because the
// widget is mounted with `v-if`: an Audio element owned by the component is
// rebuilt from scratch on every call, and so is any listener left waiting to
// retry a playback the browser refused.
let audio = null;
let wantsToRing = false;
let waitingForGesture = false;
let blockedHandler = () => {};

const element = () => {
  if (!audio) {
    audio = new Audio(RINGTONE_URL);
    audio.loop = true;
    audio.volume = 1;
  }
  return audio;
};

// Autoplay is gated on the document having been interacted with since it
// loaded. A dashboard restored when the browser opened, or reloaded and then
// left alone, has no such gesture and `play()` is rejected — until now
// silently, which is why agents reported calls that did not ring at all.
//
// So say so, and retry on the first gesture anywhere in the page: the moment
// the agent touches something, a call still ringing starts to ring.
const attemptPlay = () => {
  element()
    .play()
    .catch(() => {
      blockedHandler();
      if (waitingForGesture) return;

      waitingForGesture = true;
      const retry = () => {
        document.removeEventListener('pointerdown', retry);
        document.removeEventListener('keydown', retry);
        waitingForGesture = false;
        if (wantsToRing) attemptPlay();
      };

      document.addEventListener('pointerdown', retry);
      document.addEventListener('keydown', retry);
    });
};

export const startRingtone = (onBlocked = () => {}) => {
  wantsToRing = true;
  // Kept at module level so a retry that outlives one mount of the widget
  // reports to the component that is on screen now, not to a dead one.
  blockedHandler = onBlocked;
  attemptPlay();
};

export const stopRingtone = () => {
  wantsToRing = false;
  if (!audio) return;

  audio.pause();
  audio.currentTime = 0;
};
