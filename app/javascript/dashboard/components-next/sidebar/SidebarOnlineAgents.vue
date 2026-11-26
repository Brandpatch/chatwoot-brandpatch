<script setup>
// [brandpatch] Sidebar panel listing the agents that are online or busy right
// now (COM-1757). Presence is kept fresh by the ActionCable `presence.update`
// event (helper/actionCable.js -> agents/updatePresence), so this component
// only loads the agents once and derives the list from the store.
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';

defineProps({
  isCollapsed: {
    type: Boolean,
    default: false,
  },
});

const FOLDED_STORAGE_KEY = 'brandpatch.sidebar.onlineAgents.folded';
const STATUS_ORDER = { online: 0, busy: 1 };

const { t } = useI18n();
const store = useStore();
const agents = useMapGetter('agents/getAgents');

const readFolded = () => {
  try {
    return window.localStorage.getItem(FOLDED_STORAGE_KEY) === 'true';
  } catch {
    return false;
  }
};

const isFolded = ref(readFolded());

const toggleFolded = () => {
  isFolded.value = !isFolded.value;
  try {
    window.localStorage.setItem(FOLDED_STORAGE_KEY, String(isFolded.value));
  } catch {
    // Storage unavailable (private mode, blocked site data): keep in memory.
  }
};

const displayName = agent => agent.available_name || agent.name || '';

const onlineAgents = computed(() =>
  (agents.value || [])
    .filter(agent => agent.availability_status in STATUS_ORDER)
    .sort(
      (a, b) =>
        STATUS_ORDER[a.availability_status] -
          STATUS_ORDER[b.availability_status] ||
        displayName(a).localeCompare(displayName(b))
    )
);

const count = computed(() => onlineAgents.value.length);

const collapsedTitle = computed(() => {
  const title = `${t('ONLINE_AGENTS_PANEL.TITLE')} (${count.value})`;
  if (!count.value) return `${title}\n${t('ONLINE_AGENTS_PANEL.EMPTY')}`;
  return [title, ...onlineAgents.value.map(displayName)].join('\n');
});

const statusLabels = computed(() => ({
  online: t('PROFILE_SETTINGS.FORM.AVAILABILITY.STATUS.ONLINE'),
  busy: t('PROFILE_SETTINGS.FORM.AVAILABILITY.STATUS.BUSY'),
}));

onMounted(() => {
  store.dispatch('agents/get');
});
</script>

<template>
  <div
    v-if="isCollapsed"
    data-test-id="online-agents-collapsed"
    class="flex relative items-center justify-center size-8 rounded-lg text-xs font-medium text-n-slate-11"
    :title="collapsedTitle"
  >
    <span>{{ count }}</span>
    <span
      class="absolute top-1 ltr:right-1 rtl:left-1 size-1.5 rounded-full"
      :class="count ? 'bg-n-teal-10' : 'bg-n-slate-8'"
    />
  </div>
  <div v-else data-test-id="online-agents" class="flex flex-col w-full px-2">
    <button
      type="button"
      data-test-id="online-agents-toggle"
      class="flex items-center gap-2 w-full h-8 px-2 rounded-lg text-sm font-medium text-n-slate-11 hover:bg-n-alpha-2"
      :aria-expanded="!isFolded"
      @click="toggleFolded"
    >
      <span class="size-2 rounded-full flex-shrink-0 bg-n-teal-10" />
      <span class="truncate">{{ t('ONLINE_AGENTS_PANEL.TITLE') }}</span>
      <span
        data-test-id="online-agents-count"
        class="text-xs text-n-slate-10 tabular-nums"
      >
        {{ count }}
      </span>
      <Icon
        icon="i-lucide-chevron-down"
        class="size-4 ms-auto flex-shrink-0 transition-transform"
        :class="{ 'ltr:-rotate-90 rtl:rotate-90': isFolded }"
      />
    </button>
    <template v-if="!isFolded">
      <p
        v-if="!count"
        data-test-id="online-agents-empty"
        class="px-2 py-1 m-0 text-xs text-n-slate-10"
      >
        {{ t('ONLINE_AGENTS_PANEL.EMPTY') }}
      </p>
      <ul
        v-else
        class="flex flex-col gap-0.5 m-0 p-0 list-none max-h-48 overflow-y-auto"
      >
        <li
          v-for="agent in onlineAgents"
          :key="agent.id"
          data-test-id="online-agents-item"
          class="flex items-center gap-2 px-2 py-1 min-w-0 text-sm text-n-slate-12"
          :title="`${displayName(agent)} · ${statusLabels[agent.availability_status]}`"
        >
          <Avatar
            :name="displayName(agent)"
            :src="agent.thumbnail"
            :status="agent.availability_status"
            :size="20"
            rounded-full
          />
          <span class="truncate">{{ displayName(agent) }}</span>
        </li>
      </ul>
    </template>
  </div>
</template>
