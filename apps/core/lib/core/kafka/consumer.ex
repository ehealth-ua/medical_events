defmodule Core.Kafka.Consumer do
  @moduledoc false

  alias Core.Patients
  alias Core.Request
  alias Core.Requests
  alias Core.Requests.VisitCreateRequest
  alias Core.Validators.Signature
  require Logger

  @digital_signature Application.get_env(:core, :microservices)[:digital_signature]

  @doc """
  TODO: add digital signature error handling
  """
  def consume(%VisitCreateRequest{id: id, signed_data: signed_data} = request) do
    with {_, {:ok, request}} <- {:request, Requests.get_by_id(id)},
         {:ok, %{"data" => data}} <- @digital_signature.decode(signed_data, []),
         {:ok, %{"content" => content, "signer" => signer}} <- Signature.validate(data) do
      Patients.consume_create_visit(content)
    else
      {:request, _} ->
        response = "Can't get request by id #{id}"
        Logger.warn(fn -> response end)
        Requests.update(id, Request.status(:failed), response)
        :ok
    end
  end

  def consume(value) do
    Logger.warn(fn ->
      "unknown kafka event #{IO.inspect(value)}"
    end)

    :ok
  end
end
