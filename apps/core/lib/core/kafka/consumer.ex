defmodule Core.Kafka.Consumer do
  @moduledoc false

  alias Core.Requests.VisitCreateRequest
  alias Core.Validators.Signature
  require Logger

  @digital_signature Application.get_env(:core, :endpoints)[:digital_signature]

  def consume(%VisitCreateRequest{signed_data: signed_data} = request) do
    with {:ok, %{"data" => data}} <- @digital_signature.decode(signed_data, []),
         {:ok, %{"content" => content, "signer" => signer}} <- Signature.validate(data) do
      IO.inspect(request)
      System.halt()
    end
  end

  def consumer(value) do
    Logger.warn(fn ->
      "unknown kafka event #{IO.inspect(value)}"
    end)

    :ok
  end
end
