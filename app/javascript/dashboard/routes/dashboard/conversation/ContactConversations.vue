<script setup>
import { computed, ref, watch, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { frontendURL, conversationUrl } from 'dashboard/helper/URLHelper';
import {
  isOnMentionsView,
  isOnUnattendedView,
  isOnFoldersView,
} from 'dashboard/store/modules/conversations/helpers/actionHelpers';
import ConversationCard from 'dashboard/components/widgets/conversation/ConversationCard.vue';
import ContextMenu from 'dashboard/components/ui/ContextMenu.vue';
import ConversationContextMenu from 'dashboard/components/widgets/conversation/contextMenu/Index.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import TabBar from 'dashboard/components-next/tabbar/TabBar.vue';
import {
  CONVERSATION_CALL_FILTER,
  buildCallFilterTabs,
  filterConversationsByCalls,
} from 'dashboard/helper/conversationCalls';

const props = defineProps({
  contactId: { type: [String, Number], required: true },
  conversationId: { type: [String, Number], required: true },
});

const store = useStore();
const route = useRoute();
const router = useRouter();

const currentChat = useMapGetter('getSelectedChat');
const uiFlags = useMapGetter('contactConversations/getUIFlags');

const contactGetter = useMapGetter('contacts/getContact');
const inboxGetter = useMapGetter('inboxes/getInbox');

const activeInbox = useMapGetter('getSelectedInbox');
const inboxesList = useMapGetter('inboxes/getInboxes');
const showInboxName = computed(
  () => !activeInbox.value && inboxesList.value.length > 1
);

const contactConversationGetter = useMapGetter(
  'contactConversations/getContactConversation'
);
const conversations = computed(() =>
  contactConversationGetter.value(props.contactId)
);

const previousConversations = computed(() =>
  conversations.value.filter(c => c.id !== Number(props.conversationId))
);

// A contact's history mixes chats and calls in the same conversations, so the
// only useful cut is whether a conversation carries calls at all. Tabs render
// only once there is at least one, which keeps the panel unchanged for
// accounts that never use voice.
const { t } = useI18n();
const callFilter = ref(CONVERSATION_CALL_FILTER.ALL);
const callFilterTabs = computed(() =>
  buildCallFilterTabs(previousConversations.value, t, { withCounts: false })
);
const activeCallFilterIndex = computed(() =>
  Math.max(
    callFilterTabs.value.findIndex(tab => tab.key === callFilter.value),
    0
  )
);
const visibleConversations = computed(() =>
  filterConversationsByCalls(previousConversations.value, callFilter.value)
);

const activeContextChat = ref(null);
const showContextMenu = ref(false);
const contextMenu = ref({ x: null, y: null });

const buildConversationUrl = conversationId => {
  const {
    params: { accountId, inbox_id: inboxId, label, teamId },
    name,
  } = route;

  let conversationType = '';
  if (isOnMentionsView({ route: { name } })) {
    conversationType = 'mention';
  } else if (isOnUnattendedView({ route: { name } })) {
    conversationType = 'unattended';
  }

  return frontendURL(
    conversationUrl({
      accountId,
      activeInbox: inboxId,
      id: conversationId,
      label,
      teamId,
      foldersId: isOnFoldersView({ route: { name } }) ? route.params.id : 0,
      conversationType,
    })
  );
};

const conversationPath = computed(() => {
  if (!activeContextChat.value) return '';
  return buildConversationUrl(activeContextChat.value.id);
});

const onCardClick = (conversation, e) => {
  const path = buildConversationUrl(conversation.id);
  if (!path) return;

  if (e.metaKey || e.ctrlKey) {
    e.preventDefault();
    window.open(
      `${window.chatwootConfig.hostURL}${path}`,
      '_blank',
      'noopener,noreferrer'
    );
    return;
  }

  router.push({ path });
};

const openContextMenu = (conversation, e) => {
  e.preventDefault();
  activeContextChat.value = conversation;
  contextMenu.value.x = e.pageX || e.clientX;
  contextMenu.value.y = e.pageY || e.clientY;
  showContextMenu.value = true;
};

const closeContextMenu = () => {
  showContextMenu.value = false;
  contextMenu.value.x = null;
  contextMenu.value.y = null;
  activeContextChat.value = null;
};

watch(
  () => props.contactId,
  (newId, oldId) => {
    if (newId && newId !== oldId) {
      showContextMenu.value = false;
      activeContextChat.value = null;
      store.dispatch('contactConversations/get', newId);
    }
  }
);

onMounted(() => {
  store.dispatch('contactConversations/get', props.contactId);
});
</script>

<template>
  <div v-if="!uiFlags.isFetching" class="">
    <TabBar
      v-if="callFilterTabs.length"
      :tabs="callFilterTabs"
      :initial-active-tab="activeCallFilterIndex"
      class="px-4 pt-1"
      @tab-changed="callFilter = $event.key"
    />
    <div v-if="!visibleConversations.length" class="no-label-message px-4 p-3">
      <span>
        {{
          previousConversations.length
            ? $t('CONVERSATION.CALL_HISTORY_FILTER.NO_MATCHES')
            : $t('CONTACT_PANEL.CONVERSATIONS.NO_RECORDS_FOUND')
        }}
      </span>
    </div>
    <div
      v-else
      class="contact-conversation--list [&>.conversation:last-child]:!border-b-0 [&>.conversation:last-child:hover]:!border-b-0 [&>.conversation:last-child]:!rounded-b-lg"
    >
      <ConversationCard
        v-for="conversation in visibleConversations"
        :key="conversation.id"
        :chat="conversation"
        :current-contact="contactGetter(conversation.meta?.sender?.id) || {}"
        :assignee="conversation.meta?.assignee || {}"
        :inbox="inboxGetter(conversation.inbox_id) || {}"
        :is-active-chat="currentChat.id === conversation.id"
        :show-inbox-name="showInboxName"
        hide-thumbnail
        compact
        @click="onCardClick(conversation, $event)"
        @contextmenu="openContextMenu(conversation, $event)"
      />
    </div>
    <ContextMenu
      v-if="showContextMenu && activeContextChat"
      :x="contextMenu.x"
      :y="contextMenu.y"
      @close="closeContextMenu"
    >
      <ConversationContextMenu
        :status="activeContextChat.status"
        :inbox-id="activeContextChat.inbox_id"
        :priority="activeContextChat.priority"
        :chat-id="activeContextChat.id"
        :has-unread-messages="activeContextChat.unread_count > 0"
        :conversation-labels="activeContextChat.labels"
        :conversation-url="conversationPath"
        :allowed-options="['open-new-tab', 'copy-link']"
        @close="closeContextMenu"
      />
    </ContextMenu>
  </div>
  <div v-else class="flex items-center justify-center py-5">
    <Spinner />
  </div>
</template>

<style lang="scss" scoped>
.no-label-message {
  @apply text-n-slate-11 mb-4;
}
</style>
