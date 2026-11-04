import {
  VOICE_CALL_STATUS,
  VOICE_CALL_DIRECTION,
} from 'dashboard/components-next/message/constants';

// The values Custom::Call#display_kind can return, which the API sends as
// `kind` on every row. That method is where a call's kind is decided; these
// are only the labels and styling for it.
export const CALL_KIND = {
  ONGOING: 'ongoing',
  INCOMING: 'incoming',
  OUTGOING: 'outgoing',
  MISSED: 'missed',
  NO_REPLY: 'no_reply',
  FAILED: 'failed',
};

// Filter chips map to the status/direction params supported by CallFinder.
export const CALL_ACTIVITY_PARAMS = {
  // Missed asks whether anybody attended, not what the provider called it, so
  // it filters on attendance rather than status — same reason as getCallKind.
  missed: {
    attended: false,
    direction: VOICE_CALL_DIRECTION.INBOUND,
  },
  no_reply: {
    status: VOICE_CALL_STATUS.NO_ANSWER,
    direction: VOICE_CALL_DIRECTION.OUTBOUND,
  },
  incoming: { direction: VOICE_CALL_DIRECTION.INBOUND },
  outgoing: { direction: VOICE_CALL_DIRECTION.OUTBOUND },
  in_progress: { status: VOICE_CALL_STATUS.IN_PROGRESS },
};
