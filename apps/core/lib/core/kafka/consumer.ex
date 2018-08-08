defmodule Core.Kafka.Consumer do
  @moduledoc false

  alias Core.Patients
  alias Core.Request
  alias Core.Requests
  alias Core.Requests.VisitCreateRequest
  require Logger

  @doc """
  TODO: add digital signature error handling
  """
  def consume(%VisitCreateRequest{_id: id} = visit_create_request) do
    case Requests.get_by_id(id) do
      {:ok, _request} ->
        with {:ok, response} <- Patients.consume_create_visit(visit_create_request) do
          Requests.update(id, Request.status(:processed), response)
          :ok
        end

      _ ->
        response = "Can't get request by id #{id}"
        Logger.warn(fn -> response end)
        Requests.update(id, Request.status(:failed), response)
        :ok
    end
  end

  def consume(value) do
    Logger.warn(fn ->
      "unknown kafka event #{inspect(value)}"
    end)

    :ok
  end
end
