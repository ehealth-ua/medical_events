defmodule Core.Patients do
  @moduledoc false

  alias Core.Kafka.Producer
  alias Core.Requests
  alias Core.Requests.VisitCreateRequest
  alias Core.Validators.JsonSchema

  def create_visit(params) do
    with :ok <- JsonSchema.validate(:visit_create, params),
         {:ok, request, visit_create_request} <- Requests.create(VisitCreateRequest, params),
         :ok <- Producer.publish_medical_event(visit_create_request) do
      {:ok, request}
    end
  end
end
