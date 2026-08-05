# [brandpatch] Exposes whether the current user is a participant of this
# conversation, so the frontend's client-side permission re-filter
# (applyRoleFilter in conversations/helpers.js) can correctly show
# conversations to agents whose Custom Role only grants
# conversation_participating_manage via participation, not assignment —
# the base conversation JSON has no participant data at all.
json.participating conversation.conversation_participants.exists?(user_id: Current.user&.id)
