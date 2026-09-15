import { computed, readonly, ref, watch, onUnmounted, onMounted } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import VoiceAPI from 'dashboard/api/channel/voice/voiceAPIClient';
import TwilioVoiceClient from 'dashboard/api/channel/voice/twilioVoiceClient';
import { useCallsStore } from 'dashboard/stores/calls';
import { useAlert } from 'dashboard/composables';
import {
  useWhatsappCallSession,
  sendWhatsappTerminateBeacon,
  cleanupWhatsappSession,
} from 'dashboard/composables/useWhatsappCallSession';
import {
  handleVoiceCallCreated,
  markCallDismissed,
  markLocalCall,
  isLocalCall,
  clearLocalCall,
} from 'dashboard/helper/voice';
import { VOICE_CALL_PROVIDERS } from 'dashboard/helper/inbox';
import {
  CONTENT_TYPES,
  VOICE_CALL_DIRECTION,
  VOICE_CALL_STATUS,
} from 'dashboard/components-next/message/constants';
import Timer from 'dashboard/helper/Timer';

const isWhatsappCall = call => call?.provider === VOICE_CALL_PROVIDERS.WHATSAPP;

// Globals attached once across all useCallSession() consumers — bubbles in a
// long thread call this composable many times, and a per-instance Timer +
// window listener stack would multiply work.
let globalsAttachedCount = 0;
let globalDurationTimer = null;
const globalCallDuration = ref(0);
let storedCallsStoreRef = null;
// Shared join lock so two surfaces (bubble + widget) clicking concurrently
// see one in-flight join, not two unrelated isJoining refs.
const globalIsJoining = ref(false);
const globalIsJoiningReadonly = readonly(globalIsJoining);

const handleBeforeUnloadGlobal = event => {
  const store = storedCallsStoreRef;
  if (!store) return;
  if (!store.hasActiveCall && !store.hasIncomingCall) return;
  event.preventDefault();
  event.returnValue = '';
};
const handlePageHideGlobal = () => sendWhatsappTerminateBeacon();
const handleTwilioDisconnectedGlobal = () =>
  storedCallsStoreRef?.clearActiveCall();

const attachGlobalsOnFirstMount = callsStore => {
  globalsAttachedCount += 1;
  if (globalsAttachedCount > 1) return;
  storedCallsStoreRef = callsStore;
  globalDurationTimer = new Timer(elapsed => {
    globalCallDuration.value = elapsed;
  });
  TwilioVoiceClient.addEventListener(
    'call:disconnected',
    handleTwilioDisconnectedGlobal
  );
  window.addEventListener('beforeunload', handleBeforeUnloadGlobal);
  window.addEventListener('pagehide', handlePageHideGlobal);
};

const detachGlobalsOnLastUnmount = () => {
  globalsAttachedCount -= 1;
  if (globalsAttachedCount > 0) return;
  globalDurationTimer?.stop();
  globalDurationTimer = null;
  globalCallDuration.value = 0;
  storedCallsStoreRef = null;
  TwilioVoiceClient.removeEventListener(
    'call:disconnected',
    handleTwilioDisconnectedGlobal
  );
  window.removeEventListener('beforeunload', handleBeforeUnloadGlobal);
  window.removeEventListener('pagehide', handlePageHideGlobal);
};

// Build the action surface used by both the root session composable and the
// lighter useCallActions consumer. All state is module-scoped — the actions
// don't depend on per-instance refs, so they're cheap to call from anywhere.
const buildCallActions = ({ callsStore, whatsappSession, t }) => {
  const findCall = callSid => callsStore.calls.find(c => c.callSid === callSid);

  const endCall = async ({ conversationId, inboxId, callSid }) => {
    const call = findCall(callSid);
    if (isWhatsappCall(call)) {
      // Pass call.callId so a wiped module state (e.g. a prior accept attempt
      // tore down the WebRTC session) doesn't stop us hitting /terminate.
      await whatsappSession.endActiveCall(call?.callId);
      globalDurationTimer?.stop();
      callsStore.clearActiveCall();
      return;
    }

    // try/finally so a failed leaveConference (e.g. backend 5xx) still
    // tears down the local Device and UI state — otherwise the call stays
    // visually active with the mic open.
    try {
      await VoiceAPI.leaveConference({ inboxId, conversationId, callSid });
    } finally {
      TwilioVoiceClient.endClientCall();
      globalDurationTimer?.stop();
      callsStore.clearActiveCall();
      clearLocalCall(callSid);
    }
  };

  const joinCall = async ({ conversationId, inboxId, callSid }) => {
    if (globalIsJoining.value) return null;

    // One join per call, ever. globalIsJoining only covers an attempt still in
    // flight, so three firings half a second apart all got through — and each
    // one dialled a fresh leg whose device initialization destroyed the leg
    // already inside the conference. The agent is the participant that starts
    // the conference, so losing their leg ended it, and the customer answered
    // into a room that no longer existed and heard hold music.
    //
    // isLocalCall names the call this tab owns: set before the first await and
    // cleared by every failure path, so it blocks a duplicate of a join that
    // worked without blocking a retry of one that did not — which is what the
    // join button on the card needs.
    if (isLocalCall(callSid)) return null;

    const call = findCall(callSid);
    // Outbound *WhatsApp* calls have no separate join step — the offer was
    // sent at initiate time and the answer is applied by the cable handler.
    // Routing through acceptIncomingCall here would call prepareInboundAnswer →
    // cleanup() and destroy the live outbound session. Outbound *Twilio*
    // calls still need joinConference + joinClientCall (FloatingCallWidget
    // auto-joins them), so don't short-circuit those.
    if (
      call?.callDirection === VOICE_CALL_DIRECTION.OUTBOUND &&
      isWhatsappCall(call)
    ) {
      return null;
    }

    globalIsJoining.value = true;
    try {
      if (isWhatsappCall(call)) {
        await whatsappSession.acceptIncomingCall({
          callId: call.callId,
          sdpOffer: call.sdpOffer,
          iceServers: call.iceServers,
        });
        callsStore.setCallActive(callSid);
        globalDurationTimer?.start();
        return { callId: call.callId };
      }

      // Claim the call before any await: device initialization fetches a token
      // and registers with Twilio, and an account-wide broadcast arriving in
      // that window (voice_call.accepted from this same tab, or the
      // ring_reassigned of an escalation this click just raced) would otherwise
      // not recognize the call as ours and tear it down mid-join.
      // Mirrors useWhatsappCallSession's activeCallId.
      markLocalCall(callSid);

      const device = await TwilioVoiceClient.initializeDevice(inboxId);
      if (!device) {
        clearLocalCall(callSid);
        return null;
      }

      // The call can die while we are still getting here — an outbound number
      // that does not exist fails in well under a second — and the store drops
      // it the moment that lands. Connecting afterwards puts the agent alone in
      // a conference nobody else will join, playing the provider's hold music
      // with no card left to hang up from. Checked after each await because the
      // teardown that races us runs before the Device exists, so it has nothing
      // to disconnect and cannot undo this later.
      if (!findCall(callSid)) {
        clearLocalCall(callSid);
        return null;
      }

      const joinResponse = await VoiceAPI.joinConference({
        conversationId,
        inboxId,
        callSid,
      });

      if (!findCall(callSid)) {
        clearLocalCall(callSid);
        return null;
      }

      const connection = await TwilioVoiceClient.joinClientCall({
        to: joinResponse?.conference_sid,
        conversationId,
        callSid,
      });

      // joinClientCall returns null when the Device is gone or the conference
      // sid never arrived, having dialled nothing at all. Marking the call
      // active then told the interface the agent was in a call they were not
      // in: a mute button over silence, and a hang up for a conference they
      // never entered.
      if (!connection) {
        clearLocalCall(callSid);
        useAlert(t('CONTACT_PANEL.CALL_FAILED'));
        return null;
      }

      callsStore.setCallActive(callSid);
      globalDurationTimer?.start();

      return { conferenceSid: joinResponse?.conference_sid };
    } catch (error) {
      useAlert(error?.response?.data?.error || t('CONTACT_PANEL.CALL_FAILED'));
      if (!isWhatsappCall(call)) clearLocalCall(callSid);
      // 409 = the call already ended before accept landed (e.g. caller hung up mid-ring).
      if (error?.response?.status === 409) {
        TwilioVoiceClient.endClientCall();
        markCallDismissed(callSid);
        callsStore.dismissCall(callSid);
      } else if (!isWhatsappCall(call)) {
        // Tear down the Twilio Device on any other join error so a retry
        // starts from a clean state — joinClientCall can leave the device
        // half-initialized after a network blip.
        TwilioVoiceClient.endClientCall();
      }
      // eslint-disable-next-line no-console
      console.error('Failed to join call:', error);
      // Drop any half-built WebRTC state so the next click starts fresh.
      cleanupWhatsappSession();
      return null;
    } finally {
      globalIsJoining.value = false;
    }
  };

  // Takes the call the card is showing rather than a sid to look up again. The
  // store entry can already be gone by the time the agent presses — that is
  // how a card gets stranded in the first place — and the lookup then fell
  // through to endClientCall(), which pokes a local Device that is not there
  // and never tells the server. Reported as a hang up button pressed many
  // times with nothing happening, and confirmed by there being no DELETE in
  // the logs for that call.
  //
  // A failure now keeps the card so the agent can press again, which is what
  // this function always claimed to do: the dismissal used to run in a
  // `finally`, so a request that failed looked exactly like one that worked.
  const rejectIncomingCall = async call => {
    const callSid = call?.callSid;
    if (!callSid) return;

    try {
      if (isWhatsappCall(call) && call?.callId) {
        if (call.callDirection === VOICE_CALL_DIRECTION.OUTBOUND) {
          // Outbound calls that are still ringing must be terminated, not
          // rejected (reject is the inbound-side verb on Meta's API).
          await whatsappSession.endActiveCall(call.callId);
        } else {
          await whatsappSession.rejectIncomingCall(call.callId);
        }
      } else if (call.inboxId && call.conversationId) {
        // Twilio incoming reject: agent hasn't joined the Device yet, so
        // endClientCall is a no-op. The backend hands the call to the next
        // eligible agent and closes this agent's turn as rejected; the caller
        // stays in the conference throughout.
        await VoiceAPI.leaveConference({
          inboxId: call.inboxId,
          conversationId: call.conversationId,
          callSid,
        });
      } else {
        TwilioVoiceClient.endClientCall();
      }
    } catch (error) {
      useAlert(error?.response?.data?.error || t('CONTACT_PANEL.CALL_FAILED'));
      return;
    }

    // Drop the card from this agent's widget — the call is no longer theirs —
    // but deliberately do NOT markCallDismissed: a rejected Twilio call is
    // still live and escalating, and that set filters the sid out of every
    // later event for the whole session. Marking it here left the agent blind
    // to the call moving on, which read as "the reject did nothing". Terminal
    // calls are still marked, from the cable handlers and the status-change
    // path where the call really is over.
    if (isWhatsappCall(call)) markCallDismissed(callSid);
    callsStore.dismissCall(callSid);
  };

  return { endCall, joinCall, rejectIncomingCall };
};

const buildReactiveSurface = callsStore => {
  const activeCall = computed(() => callsStore.activeCall);
  const incomingCalls = computed(() => callsStore.incomingCalls);
  const hasActiveCall = computed(() => callsStore.hasActiveCall);
  const formattedCallDuration = computed(() => {
    const total = globalCallDuration.value;
    const minutes = Math.floor(total / 60);
    const seconds = total % 60;
    return `${minutes.toString().padStart(2, '0')}:${seconds.toString().padStart(2, '0')}`;
  });
  return {
    activeCall,
    incomingCalls,
    hasActiveCall,
    isJoining: globalIsJoiningReadonly,
    formattedCallDuration,
  };
};

// Root-mount composable. Call once at the dashboard root (FloatingCallWidget
// is the natural anchor — always mounted, lifetime spans the whole session).
// This is the only path that registers global window/Twilio listeners and
// owns the duration Timer.
export function useCallSession() {
  const store = useStore();
  const callsStore = useCallsStore();
  const whatsappSession = useWhatsappCallSession();
  const { t } = useI18n();

  const reactive = buildReactiveSurface(callsStore);

  // Cable broadcasts (voice_call.incoming / message.created) are one-shot, so
  // on a hard refresh they leave the calls store empty. Seed it from any
  // ringing voice_call message in the conversation cache. handleVoiceCallCreated
  // skips calls already dismissed (locally or via a real-time accepted/ended
  // event) so they don't re-pop on the next conversation update.
  const seedCallsFromHydratedMessages = () => {
    const conversations = store.getters.getAllConversations || [];
    const currentUserId = store.getters.getCurrentUserID;
    const currentUserAvailability = store.getters.getCurrentUserAvailability;
    conversations.forEach(conv => {
      (conv.messages || []).forEach(msg => {
        if (msg.content_type !== CONTENT_TYPES.VOICE_CALL) return;
        if (msg.call?.status !== VOICE_CALL_STATUS.RINGING) return;
        handleVoiceCallCreated(msg, currentUserId, currentUserAvailability);
      });
    });
  };

  watch(
    reactive.hasActiveCall,
    active => {
      if (active) {
        globalDurationTimer?.start();
      } else {
        globalDurationTimer?.stop();
        globalCallDuration.value = 0;
      }
    },
    { immediate: true }
  );

  onMounted(() => {
    attachGlobalsOnFirstMount(callsStore);
    seedCallsFromHydratedMessages();
  });

  // Re-seed when conversations stream in after mount; addCall merges by callSid
  // and dismissed sids are filtered, so this is idempotent.
  watch(
    () => store.getters.getAllConversations?.length,
    () => seedCallsFromHydratedMessages()
  );

  onUnmounted(() => detachGlobalsOnLastUnmount());

  const actions = buildCallActions({ callsStore, whatsappSession, t });

  return { ...reactive, ...actions };
}

// Lightweight consumer for components that need to read state and trigger
// actions but should NOT mount global listeners (e.g., per-message bubbles
// rendered in a thread). Reads from the same module-level state that
// useCallSession owns, so the duration timer and dismissed set stay coherent.
export function useCallActions() {
  const callsStore = useCallsStore();
  const whatsappSession = useWhatsappCallSession();
  const { t } = useI18n();

  const reactive = buildReactiveSurface(callsStore);
  const actions = buildCallActions({ callsStore, whatsappSession, t });

  return { ...reactive, ...actions };
}
