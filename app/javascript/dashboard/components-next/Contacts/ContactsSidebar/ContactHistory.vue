<script setup>
import { computed, ref } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';

import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import ConversationCard from 'dashboard/components-next/Conversation/ConversationCard/ConversationCard.vue';
import TabBar from 'dashboard/components-next/tabbar/TabBar.vue';
import {
  CONVERSATION_CALL_FILTER,
  buildCallFilterTabs,
  filterConversationsByCalls,
} from 'dashboard/helper/conversationCalls';

const { t } = useI18n();
const route = useRoute();

const conversations = useMapGetter(
  'contactConversations/getAllConversationsByContactId'
);
const contactsById = useMapGetter('contacts/getContactById');
const stateInbox = useMapGetter('inboxes/getInboxById');
const accountLabels = useMapGetter('labels/getLabels');

const accountLabelsValue = computed(() => accountLabels.value);

const uiFlags = useMapGetter('contactConversations/getUIFlags');
const isFetching = computed(() => uiFlags.value.isFetching);

const contactConversations = computed(() =>
  conversations.value(route.params.contactId)
);

// Same cut as the conversation side panel, from the same helper, so the two
// histories can never classify a conversation differently. This tab is wide
// enough to carry the counts as well.
const callFilter = ref(CONVERSATION_CALL_FILTER.ALL);
const callFilterTabs = computed(() =>
  buildCallFilterTabs(contactConversations.value, t, { withCounts: true })
);
const activeCallFilterIndex = computed(() =>
  Math.max(
    callFilterTabs.value.findIndex(tab => tab.key === callFilter.value),
    0
  )
);
const visibleConversations = computed(() =>
  filterConversationsByCalls(contactConversations.value, callFilter.value)
);
</script>

<template>
  <div
    v-if="isFetching"
    class="flex items-center justify-center py-10 text-n-slate-11"
  >
    <Spinner />
  </div>
  <div v-else-if="contactConversations.length > 0">
    <TabBar
      v-if="callFilterTabs.length"
      :tabs="callFilterTabs"
      :initial-active-tab="activeCallFilterIndex"
      class="px-6 pb-2"
      @tab-changed="callFilter = $event.key"
    />
    <p
      v-if="!visibleConversations.length"
      class="px-6 py-10 text-sm leading-6 text-center text-n-slate-11"
    >
      {{ t('CONVERSATION.CALL_HISTORY_FILTER.NO_MATCHES') }}
    </p>
    <div
      v-else
      class="px-6 divide-y divide-n-strong [&>*:hover]:!border-y-transparent [&>*:hover+*]:!border-t-transparent"
    >
      <ConversationCard
        v-for="conversation in visibleConversations"
        :key="conversation.id"
        :conversation="conversation"
        :contact="contactsById(conversation.meta.sender.id)"
        :state-inbox="stateInbox(conversation.inboxId)"
        :account-labels="accountLabelsValue"
        class="rounded-none hover:rounded-xl hover:bg-n-alpha-1 dark:hover:bg-n-alpha-3"
      />
    </div>
  </div>
  <p v-else class="px-6 py-10 text-sm leading-6 text-center text-n-slate-11">
    {{ t('CONTACTS_LAYOUT.SIDEBAR.HISTORY.EMPTY_STATE') }}
  </p>
</template>
