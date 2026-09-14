<script setup>
import { computed, nextTick, onBeforeUnmount, onMounted, ref, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useStore } from 'vuex';
import { useDraggable } from '@vueuse/core';
import { useCallSession } from 'dashboard/composables/useCallSession';
import { setWhatsappCallMuted } from 'dashboard/composables/useWhatsappCallSession';
import TwilioVoiceClient from 'dashboard/api/channel/voice/twilioVoiceClient';
import { frontendURL, conversationUrl } from 'dashboard/helper/URLHelper';
import { VOICE_CALL_PROVIDERS } from 'dashboard/helper/inbox';
import { VOICE_CALL_DIRECTION } from 'dashboard/components-next/message/constants';
import WindowVisibilityHelper from 'dashboard/helper/AudioAlerts/WindowVisibilityHelper';
import CallCard from 'dashboard/components-next/call/CallCard.vue';
import MinimizedCallBubble from 'dashboard/components-next/call/MinimizedCallBubble.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import { LocalStorage } from 'shared/helpers/localStorage';
import { LOCAL_STORAGE_KEYS } from 'dashboard/constants/localStorage';
import countriesList from 'shared/constants/countries.js';

const RINGTONE_URL = '/audio/dashboard/ringtone.mp3';

const route = useRoute();
const router = useRouter();
const store = useStore();

const {
  activeCall,
  incomingCalls,
  hasActiveCall,
  isJoining,
  joinCall,
  endCall: endCallSession,
  rejectIncomingCall,
  formattedCallDuration,
} = useCallSession();

// The widget sits over the reply box, so an agent writing a note while on a
// call cannot reach what they are typing. It can be dragged anywhere and
// collapsed to a pill, and both choices are remembered per browser.
const VIEWPORT_MARGIN = 16;
// A pointer that travelled less than this between press and release was a
// click, not a drag — expanding the pill should not need a perfectly still hand.
const CLICK_SLOP = 3;

const widgetRef = ref(null);
const dragHandleRef = ref(null);

const storedPosition = ref(
  LocalStorage.get(LOCAL_STORAGE_KEYS.VOICE_WIDGET_POSITION)
);
const isMinimized = ref(
  Boolean(LocalStorage.get(LOCAL_STORAGE_KEYS.VOICE_WIDGET_MINIMIZED))
);

// Keeps the widget fully on screen: a position saved on a wide window would
// otherwise put it out of reach on a narrow one.
const clampToViewport = ({ x, y }) => {
  const rect = widgetRef.value?.getBoundingClientRect();
  if (!rect) return { x, y };

  const maxX = Math.max(
    VIEWPORT_MARGIN,
    window.innerWidth - rect.width - VIEWPORT_MARGIN
  );
  const maxY = Math.max(
    VIEWPORT_MARGIN,
    window.innerHeight - rect.height - VIEWPORT_MARGIN
  );

  return {
    x: Math.min(Math.max(x, VIEWPORT_MARGIN), maxX),
    y: Math.min(Math.max(y, VIEWPORT_MARGIN), maxY),
  };
};

const persistPosition = value => {
  storedPosition.value = value;
  LocalStorage.set(LOCAL_STORAGE_KEYS.VOICE_WIDGET_POSITION, value);
};

let pointerOrigin = null;
let wasDragged = false;

const { position, isDragging } = useDraggable(widgetRef, {
  handle: dragHandleRef,
  preventDefault: true,
  initialValue: storedPosition.value ?? { x: 0, y: 0 },
  onStart: (_position, event) => {
    pointerOrigin = { x: event.clientX, y: event.clientY };
    // Until the first drag the widget is placed by CSS, so `position` still
    // holds the seed value. Anchor it to where the widget actually is, or
    // switching to absolute coordinates jumps it to the top left corner.
    const rect = widgetRef.value?.getBoundingClientRect();
    if (rect) position.value = { x: rect.left, y: rect.top };
  },
  onEnd: (_position, event) => {
    wasDragged =
      Math.abs(event.clientX - pointerOrigin.x) > CLICK_SLOP ||
      Math.abs(event.clientY - pointerOrigin.y) > CLICK_SLOP;
    const clamped = clampToViewport(position.value);
    position.value = clamped;
    persistPosition(clamped);
  },
});

const hasCustomPosition = computed(
  () => Boolean(storedPosition.value) || isDragging.value
);

const positionStyle = computed(() =>
  hasCustomPosition.value
    ? { left: `${position.value.x}px`, top: `${position.value.y}px` }
    : undefined
);

const expandFromBubble = () => {
  // The pill is its own drag handle, so a release that moved must not also
  // count as the click that expands it.
  if (wasDragged) {
    wasDragged = false;
    return;
  }
  isMinimized.value = false;
};

// Re-clamp whenever the widget's own height or the viewport changes: a second
// call stacking in makes it taller, which can push it past the bottom edge.
const reclamp = async () => {
  if (!storedPosition.value) return;

  await nextTick();
  const clamped = clampToViewport(storedPosition.value);
  position.value = clamped;
  persistPosition(clamped);
};

onMounted(() => window.addEventListener('resize', reclamp));
onBeforeUnmount(() => window.removeEventListener('resize', reclamp));

watch(isMinimized, value => {
  LocalStorage.set(LOCAL_STORAGE_KEYS.VOICE_WIDGET_MINIMIZED, value);
  reclamp();
});

watch(
  () => incomingCalls.value.length,
  (count, previous) => {
    // A call the agent has not seen yet must not stay hidden behind the pill.
    if (count > previous) isMinimized.value = false;
    reclamp();
  }
);

// Mute routes by provider: WhatsApp toggles the local mic track, Twilio uses
// the Voice SDK connection's native mute. Both surface the same button.
const isMuted = ref(false);
const isWhatsappActive = computed(
  () => activeCall.value?.provider === VOICE_CALL_PROVIDERS.WHATSAPP
);

const primaryIncomingCall = computed(() =>
  hasActiveCall.value ? null : incomingCalls.value[0] || null
);

const stackedIncomingCalls = computed(() =>
  hasActiveCall.value ? incomingCalls.value : incomingCalls.value.slice(1)
);

const mainCardState = computed(() => {
  if (hasActiveCall.value) return VOICE_CALL_DIRECTION.ONGOING;
  const direction = primaryIncomingCall.value?.callDirection;
  return direction === VOICE_CALL_DIRECTION.OUTBOUND
    ? VOICE_CALL_DIRECTION.OUTGOING
    : VOICE_CALL_DIRECTION.INCOMING;
});

// Stacked cards are always non-active (ringing) calls, so reflect each call's
// real direction: an outbound call renders as OUTGOING, which is what decides
// its icon and label and keeps the incoming-only accept button off a call the
// agent placed themselves.
const stackedCardState = call =>
  call?.callDirection === VOICE_CALL_DIRECTION.OUTBOUND
    ? VOICE_CALL_DIRECTION.OUTGOING
    : VOICE_CALL_DIRECTION.INCOMING;

const toggleMute = () => {
  isMuted.value = !isMuted.value;
  if (isWhatsappActive.value) {
    setWhatsappCallMuted(isMuted.value);
  } else {
    TwilioVoiceClient.setMuted(isMuted.value);
  }
};

watch(hasActiveCall, active => {
  if (!active) isMuted.value = false;
});

// Convert ISO 3166-1 alpha-2 country code (e.g. "US") to its regional indicator
// flag emoji. Returns empty string if the code is missing or malformed.
const countryCodeToFlag = code => {
  if (!code || code.length !== 2) return '';
  const base = 0x1f1e6;
  const offset = 'A'.charCodeAt(0);
  return String.fromCodePoint(
    ...code
      .toUpperCase()
      .split('')
      .map(c => base + (c.charCodeAt(0) - offset))
  );
};

const getCallInfo = call => {
  const conversation = store.getters.getConversationById(call?.conversationId);
  // Look up inbox from the call's own inboxId — the conversation can drop out
  // of the Vuex store when the user navigates between inbox views, so going
  // through `conversation.inbox_id` would lose the inbox name (and fall back
  // to the literal "Customer support" string).
  const inbox = store.getters['inboxes/getInbox'](call?.inboxId);
  const sender = conversation?.meta?.sender;
  // `caller` is the snapshot captured when the call first landed (from the
  // message sender or the WhatsApp cable payload). It outlives the
  // conversation being in the store, so prefer it for display.
  const caller = call?.caller;
  const additional =
    sender?.additional_attributes || caller?.additionalAttributes || {};
  const city = additional.city || '';
  const countryCode = additional.country_code || '';
  const country =
    additional.country ||
    countriesList.find(c => c.id === countryCode.toUpperCase())?.name ||
    '';
  // Prefer the richest available location string ("City, Country"); fall back to
  // whichever single field is present; finally fall back to the inbox name so
  // there's always something to show.
  const locationParts = [city, country].filter(Boolean);
  const location =
    locationParts.join(', ') || inbox?.name || 'Customer support';
  return {
    conversation,
    inbox,
    contactName:
      caller?.name ||
      sender?.name ||
      caller?.phone ||
      sender?.phone_number ||
      'Unknown caller',
    phoneNumber: caller?.phone || sender?.phone_number || '',
    inboxName: inbox?.name || 'Customer support',
    location,
    countryFlag: countryCodeToFlag(countryCode),
    hasLocation: locationParts.length > 0,
    avatar: caller?.avatar || sender?.avatar || sender?.thumbnail,
  };
};

const goToConversation = call => {
  const conversationId = call?.conversationId;
  const accountId = route.params.accountId;
  if (!conversationId || !accountId) return;
  router.push({
    path: frontendURL(conversationUrl({ accountId, id: conversationId })),
  });
};

const handleEndCall = async () => {
  const call = activeCall.value;
  if (!call) return;

  const inboxId = call.inboxId || getCallInfo(call).conversation?.inbox_id;
  if (!inboxId) return;

  await endCallSession({
    conversationId: call.conversationId,
    inboxId,
    callSid: call.callSid,
  });
};

const handleJoinCall = async call => {
  if (!call || isJoining.value) return;
  const { conversation } = getCallInfo(call);

  if (hasActiveCall.value) {
    await handleEndCall();
  }

  // The conversation may not be hydrated yet (post-refresh seeding path);
  // call.inboxId already carries what joinCall needs.
  const result = await joinCall({
    conversationId: call.conversationId,
    inboxId: call.inboxId || conversation?.inbox_id,
    callSid: call.callSid,
  });

  if (result && conversation) {
    router.push({
      name: 'inbox_conversation',
      params: { conversation_id: call.conversationId },
    });
  }
};

// Auto-join outbound calls when window is visible. WhatsApp outbound has no
// separate join step (the offer was sent at initiate time and the answer is
// applied directly by the cable handler), so this only covers Twilio.
watch(
  () => incomingCalls.value[0],
  call => {
    if (
      call?.callDirection === VOICE_CALL_DIRECTION.OUTBOUND &&
      call?.provider !== VOICE_CALL_PROVIDERS.WHATSAPP &&
      !hasActiveCall.value &&
      WindowVisibilityHelper.isWindowVisible()
    ) {
      handleJoinCall(call);
    }
  },
  { immediate: true }
);

// Loop the ringtone while an inbound call is unanswered. Stop the moment any
// call is active (we joined), every inbound call cleared, or the widget tears
// down. The watcher only fires on the boolean transitioning, so additional
// ringing calls arriving while one is already ringing don't restart the audio
// — they silently stack into the UI without producing a fresh ring.
// Browser autoplay may reject the first play() if the tab has no prior
// user gesture; that's fine — the visual widget still surfaces the call.
const ringtone = new Audio(RINGTONE_URL);
ringtone.loop = true;
ringtone.volume = 1;

const stopRingtone = () => {
  ringtone.pause();
  ringtone.currentTime = 0;
};

const ringingInbound = computed(() =>
  incomingCalls.value.some(
    call => call.callDirection !== VOICE_CALL_DIRECTION.OUTBOUND
  )
);

watch(
  () => ringingInbound.value && !hasActiveCall.value,
  shouldRing => {
    if (shouldRing) {
      ringtone.play().catch(() => {});
    } else {
      stopRingtone();
    }
  },
  { immediate: true }
);

onBeforeUnmount(stopRingtone);
</script>

<template>
  <div
    v-if="incomingCalls.length || hasActiveCall"
    ref="widgetRef"
    class="fixed z-50"
    :class="[
      hasCustomPosition ? '' : 'ltr:right-4 rtl:left-4 bottom-4',
      isMinimized ? 'w-auto' : 'w-[400px]',
    ]"
    :style="positionStyle"
  >
    <!-- Collapsed: a pill the agent parks anywhere while they type. -->
    <div
      v-if="isMinimized"
      ref="dragHandleRef"
      class="cursor-grab active:cursor-grabbing"
      @click="expandFromBubble"
    >
      <MinimizedCallBubble
        :call-info="getCallInfo(activeCall || primaryIncomingCall)"
        :duration="hasActiveCall ? formattedCallDuration : ''"
        :is-ongoing="hasActiveCall"
        :extra-count="stackedIncomingCalls.length"
      />
    </div>

    <div v-else class="flex flex-col gap-3">
      <!-- Drag bar. Dragging lives here rather than on the cards so it never
           competes with the answer and hang-up buttons, which sit inches away
           and are the last thing an agent can afford to miss. -->
      <div
        class="flex items-center justify-between px-2 rounded-full bg-n-call-widget shadow-xl outline outline-1 outline-n-call-widget-border backdrop-blur-md"
      >
        <div
          ref="dragHandleRef"
          v-tooltip.top="$t('CONVERSATION.VOICE_WIDGET.DRAG_TO_MOVE')"
          class="flex flex-1 items-center py-2 cursor-grab active:cursor-grabbing"
        >
          <Icon
            icon="i-ri-drag-move-line"
            class="size-3.5 text-n-call-widget-sub-text"
          />
        </div>
        <NextButton
          v-tooltip.top="$t('CONVERSATION.VOICE_WIDGET.MINIMIZE')"
          icon="i-lucide-minus"
          slate
          ghost
          xs
          class="!rounded-full !text-n-call-widget-sub-text"
          @click="isMinimized = true"
        />
      </div>

      <!-- Stacked incoming calls (shown above the primary card) -->
      <CallCard
        v-for="call in stackedIncomingCalls"
        :key="call.callSid"
        :call="call"
        :state="stackedCardState(call)"
        :call-info="getCallInfo(call)"
        @accept="handleJoinCall(call)"
        @reject="rejectIncomingCall(call.callSid)"
        @go-to-conversation="goToConversation(call)"
      />

      <!-- Main Call Widget -->
      <CallCard
        v-if="hasActiveCall || primaryIncomingCall"
        :call="activeCall || primaryIncomingCall"
        :state="mainCardState"
        :call-info="getCallInfo(activeCall || primaryIncomingCall)"
        :duration="hasActiveCall ? formattedCallDuration : ''"
        :is-muted="isMuted"
        :show-mute="hasActiveCall"
        @accept="handleJoinCall(primaryIncomingCall)"
        @reject="rejectIncomingCall(primaryIncomingCall?.callSid)"
        @end="handleEndCall"
        @toggle-mute="toggleMute"
        @go-to-conversation="goToConversation(activeCall || primaryIncomingCall)"
      />
    </div>
  </div>
</template>
