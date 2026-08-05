# [brandpatch] Exposes whether the current user is a participant of this
# conversation, so the frontend's client-side permission re-filter
# (applyRoleFilter in conversations/helpers.js) can correctly show
# conversations to agents whose Custom Role only grants
# conversation_participating_manage via participation, not assignment —
# the base conversation JSON has no participant data at all.
json.participating conversation.conversation_participants.exists?(user_id: Current.user&.id)

if conversation.account.feature_enabled?('custom_sla') && !conversation.account.feature_enabled?('sla')
  if conversation.sla_applicable?
    json.applied_sla do
      json.partial! 'api/v1/models/applied_sla', formats: [:json], resource: conversation.applied_sla if conversation.applied_sla.present?
    end
    json.sla_events do
      json.array! conversation.sla_events do |sla_event|
        json.partial! 'api/v1/models/sla_event', formats: [:json], sla_event: sla_event
      end
    end
  else
    json.applied_sla nil
    json.sla_events []
  end
end
