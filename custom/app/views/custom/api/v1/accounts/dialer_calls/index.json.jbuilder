json.meta do
  json.current_page @calls.current_page
  json.next_page @calls.next_page
end

json.payload do
  json.array! @calls do |call|
    dialer = call.dialer
    json.call_id call.id
    json.external_id dialer['external_id']
    json.metadata dialer['metadata']
    json.phone_number call.contact.phone_number
    json.status call.display_status
    # The same label the call list and the CSV use: 'outgoing' connected,
    # 'no_reply' was not picked up, 'failed' never placed, 'ongoing' still live.
    # A voicemail that picked up reads 'outgoing' here as it does for a manual
    # call; answered_by is what tells it apart.
    json.display_kind call.display_kind
    # awaiting_agent on a finished call means the customer was never dialled.
    json.phase dialer['phase']
    json.answered_by dialer['answered_by']
    # A person picked up and talked to the agent: started_at is only stamped when
    # the customer's leg reports answered, and a machine is told apart by AMD.
    # Kept here so the consumer does not rebuild the rule from display_kind.
    json.answered call.started_at.present? && !dialer['answered_by'].to_s.start_with?('machine', 'fax')
    # The dialer's own reason (agent_did_not_join, machine) when it ended the
    # call, otherwise who hung up.
    json.end_reason dialer['end_reason'] || call.end_reason
    json.failure_reason call.failure_reason
    json.agent_id call.accepted_by_agent_id
    json.agent_name call.accepted_by_agent&.available_name
    json.agent_email call.accepted_by_agent&.email
    json.conversation_id call.conversation.display_id
    json.started_at call.started_at&.to_i
    json.duration_seconds call.duration_seconds
    json.created_at call.created_at.to_i
    json.updated_at call.updated_at.to_i
  end
end
