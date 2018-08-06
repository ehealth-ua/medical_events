defmodule Core.Patients do
  @moduledoc false

  alias Core.Mongo
  alias Core.Requests
  alias Core.Requests.VisitCreateRequest
  alias Core.Validators.JsonSchema

  @kafka_producer Application.get_env(:core, :kafka)[:producer]

  def produce_create_visit(params) do
    with :ok <- JsonSchema.validate(:visit_create, params),
         {:ok, request, visit_create_request} <- Requests.create(VisitCreateRequest, params),
         :ok <- @kafka_producer.publish_medical_event(visit_create_request) do
      {:ok, request}
    end
  end

  def consume_create_visit(content) do
  end
end
