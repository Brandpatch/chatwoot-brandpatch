/**
 * A contact's history mixes chats and calls, and there is no way to split it:
 * voice rides on the Twilio SMS channel, so one inbox serves both, and a call
 * reuses the contact's open conversation rather than opening its own. A single
 * conversation can therefore be a chat and a call at once. The only stable
 * question is whether it carries calls at all, which is what calls_count from
 * the conversation payload answers.
 *
 * The two surfaces that show this history read the same records through
 * different getters — one raw, one camelised — so the count is accepted under
 * either spelling, and the rule itself lives here so the two cannot drift.
 */

export const CONVERSATION_CALL_FILTER = {
  ALL: 'all',
  WITH_CALLS: 'with_calls',
  MESSAGES_ONLY: 'messages_only',
};

export const conversationCallsCount = conversation =>
  conversation?.callsCount ?? conversation?.calls_count ?? 0;

export const conversationHasCalls = conversation =>
  conversationCallsCount(conversation) > 0;

// A mixed conversation counts as one with calls, never as messages only, so it
// is always reachable from the filter that names it.
export const filterConversationsByCalls = (conversations, filter) => {
  if (filter === CONVERSATION_CALL_FILTER.WITH_CALLS) {
    return conversations.filter(conversationHasCalls);
  }
  if (filter === CONVERSATION_CALL_FILTER.MESSAGES_ONLY) {
    return conversations.filter(c => !conversationHasCalls(c));
  }
  return conversations;
};

// The tabs only earn their space once the contact actually has calls; for an
// account that never uses voice this stays hidden entirely.
export const buildCallFilterTabs = (conversations, t, { withCounts }) => {
  const withCalls = conversations.filter(conversationHasCalls).length;
  if (!withCalls) return [];

  const tabs = [
    {
      key: CONVERSATION_CALL_FILTER.ALL,
      label: t('CONVERSATION.CALL_HISTORY_FILTER.ALL'),
      count: conversations.length,
    },
    {
      key: CONVERSATION_CALL_FILTER.WITH_CALLS,
      label: t('CONVERSATION.CALL_HISTORY_FILTER.WITH_CALLS'),
      count: withCalls,
    },
    {
      key: CONVERSATION_CALL_FILTER.MESSAGES_ONLY,
      label: t('CONVERSATION.CALL_HISTORY_FILTER.MESSAGES_ONLY'),
      count: conversations.length - withCalls,
    },
  ];

  // The narrow side panel has no room for counts; the History tab does.
  return withCounts ? tabs : tabs.map(({ key, label }) => ({ key, label }));
};
