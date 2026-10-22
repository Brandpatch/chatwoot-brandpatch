<script setup>
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { format, fromUnixTime, isToday } from 'date-fns';
import VoiceAPI from 'dashboard/api/channel/voice/voiceAPIClient';
import SectionLayout from './SectionLayout.vue';
import Switch from 'next/switch/Switch.vue';

const { t } = useI18n();

const isPaused = ref(false);
const pausedAt = ref(null);

// Read from the server rather than from currentAccount: the key is deliberately
// absent from the core account endpoint's permitted settings, so this switch is
// the only writer and its own endpoint is the only reader.
const applyState = state => {
  isPaused.value = state.paused;
  pausedAt.value = state.paused_at ?? null;
};

// Shown so a pause nobody lifted is visible. One switch is much easier to
// forget than the 544 unassignments this replaces.
//
// Numeric on purpose. date-fns is never given a locale anywhere in this app, so
// anything with words in it — "3 hours ago", "Oct" — comes back in English and
// lands inside a translated sentence. Digits read the same in every language.
// The date joins in once the pause is no longer from today, which is the case
// worth noticing at a glance.
const pausedSince = computed(() => {
  if (!pausedAt.value) return '';

  const when = fromUnixTime(pausedAt.value);
  return format(when, isToday(when) ? 'HH:mm' : 'd/M HH:mm');
});

onMounted(async () => {
  try {
    applyState(await VoiceAPI.getInboundCallPause());
  } catch (error) {
    // Said out loud rather than left at the default: a switch silently showing
    // "not paused" while the phones are actually off is worse than no switch.
    useAlert(t('GENERAL_SETTINGS.FORM.INBOUND_CALL_PAUSE.API.LOAD_ERROR'));
  }
});

// v-model has already written the new value by the time this runs, so the ref
// holds where the switch is going, not where it came from.
const togglePause = async () => {
  const desired = isPaused.value;
  try {
    applyState(await VoiceAPI.setInboundCallPause(desired));
    useAlert(
      t(
        desired
          ? 'GENERAL_SETTINGS.FORM.INBOUND_CALL_PAUSE.API.PAUSED'
          : 'GENERAL_SETTINGS.FORM.INBOUND_CALL_PAUSE.API.RESUMED'
      )
    );
  } catch (error) {
    isPaused.value = !desired;
    useAlert(t('GENERAL_SETTINGS.FORM.INBOUND_CALL_PAUSE.API.ERROR'));
  }
};
</script>

<template>
  <SectionLayout
    :title="t('GENERAL_SETTINGS.FORM.INBOUND_CALL_PAUSE.TITLE')"
    :description="t('GENERAL_SETTINGS.FORM.INBOUND_CALL_PAUSE.NOTE')"
    with-border
  >
    <template #headerActions>
      <div class="flex items-center justify-end gap-2">
        <span v-if="isPaused && pausedSince" class="text-sm text-n-slate-11">
          {{
            t('GENERAL_SETTINGS.FORM.INBOUND_CALL_PAUSE.PAUSED_SINCE', {
              time: pausedSince,
            })
          }}
        </span>
        <Switch v-model="isPaused" @change="togglePause" />
      </div>
    </template>
  </SectionLayout>
</template>
