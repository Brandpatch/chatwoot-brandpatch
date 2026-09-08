<script setup>
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';

defineProps({
  callInfo: {
    type: Object,
    required: true,
  },
  duration: {
    type: String,
    default: '',
  },
  isOngoing: {
    type: Boolean,
    default: false,
  },
  // Calls waiting behind this one, so a minimized agent can still tell there
  // is more than one rather than finding out on expanding.
  extraCount: {
    type: Number,
    default: 0,
  },
});
</script>

<template>
  <div
    class="inline-flex items-center gap-2 p-1.5 ltr:pr-3 rtl:pl-3 rounded-full bg-n-call-widget shadow-xl outline outline-1 outline-n-call-widget-border backdrop-blur-md"
  >
    <div class="relative shrink-0">
      <Avatar :src="callInfo.avatar" :name="callInfo.contactName" :size="32" />
      <span
        v-if="extraCount"
        class="absolute -top-1 ltr:-right-1 rtl:-left-1 flex items-center justify-center min-w-4 h-4 px-1 rounded-full bg-n-ruby-9 text-white text-[10px] font-medium tabular-nums"
      >
        {{ extraCount + 1 }}
      </span>
    </div>

    <div class="flex flex-col min-w-0 leading-tight">
      <span
        class="max-w-32 text-xs font-medium text-n-call-widget-text truncate tracking-tight"
      >
        {{ callInfo.contactName }}
      </span>
      <span
        v-if="isOngoing"
        class="text-xs text-n-teal-9 tabular-nums tracking-tight"
      >
        {{ duration }}
      </span>
      <span v-else class="text-xs text-n-call-widget-sub-text tracking-tight">
        {{ $t('CONVERSATION.VOICE_WIDGET.INCOMING_CALL') }}
      </span>
    </div>

    <Icon
      icon="i-ri-drag-move-line"
      class="size-3.5 text-n-call-widget-sub-text shrink-0"
    />
  </div>
</template>
