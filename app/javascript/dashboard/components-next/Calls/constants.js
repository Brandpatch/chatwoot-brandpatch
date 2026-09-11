import {
  VOICE_CALL_STATUS,
  VOICE_CALL_DIRECTION,
  isMissedInboundVoiceCall,
} from 'dashboard/components-next/message/constants';

export const CALL_KIND = {
  ONGOING: 'ongoing',
  INCOMING: 'incoming',
  OUTGOING: 'outgoing',
  MISSED: 'missed',
  NO_REPLY: 'no_reply',
  FAILED: 'failed',
};

// The API returns display values: status (ringing/in-progress/completed/
// no-answer/failed) and direction (inbound/outbound). The list UI presents
// them as a single "kind" per row.
export const getCallKind = call => {
  if (
    [VOICE_CALL_STATUS.RINGING, VOICE_CALL_STATUS.IN_PROGRESS].includes(
      call.status
    )
  ) {
    return CALL_KIND.ONGOING;
  }
  // Failed means the call could not be connected, which is what its label
  // says. A decline connected fine, so it belongs with the missed calls below.
  if (call.status === VOICE_CALL_STATUS.FAILED) return CALL_KIND.FAILED;

  const isInbound = call.direction === VOICE_CALL_DIRECTION.INBOUND;
  if (call.status === VOICE_CALL_STATUS.NO_ANSWER) {
    return isInbound ? CALL_KIND.MISSED : CALL_KIND.NO_REPLY;
  }
  // Every other terminal inbound call nobody attended: the caller hung up while
  // it rang, which Twilio reports as 'completed', or an agent declined it.
  // Outbound always carries the agent who dialled, so it never applies there.
  if (
    isMissedInboundVoiceCall({
      status: call.status,
      hasAgent: !!call.agent,
      isInbound,
    })
  ) {
    return CALL_KIND.MISSED;
  }
  return isInbound ? CALL_KIND.INCOMING : CALL_KIND.OUTGOING;
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
