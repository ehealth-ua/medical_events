defmodule Core.Patients do
  @moduledoc false

  alias Core.Kafka.Producer
  alias Core.Requests
  alias Core.Validators.JsonSchema

  def create_visit(params) do
    with :ok <- JsonSchema.validate(:visit_create, params),
         {:ok, request} <- Requests.create(params),
         :ok <- Producer.publish_medical_event(request, params) do
      {:ok, request}
    end
  end
end
