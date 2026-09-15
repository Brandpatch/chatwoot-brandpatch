// Which Twilio call (if any) this tab is actively joining/owns.
//
// Lives in its own module because both the calls store and the voice helper
// need it, and the helper already imports the store — putting it in either one
// would close an import cycle.
let localCallSid = null;

export const markLocalCall = callSid => {
  localCallSid = callSid || null;
};

export const isLocalCall = callSid =>
  !!callSid && localCallSid != null && callSid === localCallSid;

export const clearLocalCall = callSid => {
  if (localCallSid === callSid) localCallSid = null;
};
