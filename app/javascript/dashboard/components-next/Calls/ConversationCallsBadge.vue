<script setup>
import { computed } from 'vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import { conversationCallsCount } from 'dashboard/helper/conversationCalls';

// Marks a conversation that carries voice calls. Sits on the card rather than
// in the list so both histories — the conversation side panel and the contact's
// History tab — show the same mark from the same rule.
const props = defineProps({
  conversation: { type: Object, required: true },
});

const count = computed(() => conversationCallsCount(props.conversation));
</script>

<template>
  <span
    v-if="count > 0"
    v-tooltip.left="
      $t('CONVERSATION.CALL_HISTORY_FILTER.BADGE_TOOLTIP', { count })
    "
    class="inline-flex items-center flex-shrink-0 gap-0.5 text-n-slate-11"
  >
    <Icon icon="i-ph-phone-bold" class="size-3 flex-shrink-0" />
    <span class="text-xs font-medium leading-none">{{ count }}</span>
  </span>
</template>
