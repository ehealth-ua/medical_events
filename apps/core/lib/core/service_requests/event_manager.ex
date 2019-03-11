defmodule Core.ServiceRequests.EventManager do
  @moduledoc """
  Generate map with event info
  """

  alias Core.ServiceRequest
  @entity_type "ServiceRequest"
  @event_type "StatusChangeEvent"

  @kafka_producer Application.get_env(:core, :kafka)[:producer]

  def new_event(entity_id, actor_id, status) do
    @kafka_producer.publish_to_event_manager(%{
      event_type: @event_type,
      entity_type: @entity_type,
      changed_by: actor_id,
      entity_id: to_string(entity_id),
      properties: %{"status" => %{"new_value" => status}},
      event_time: NaiveDateTime.utc_now()
    })
  end
end
