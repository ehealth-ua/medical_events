defmodule Core.Validators.LegalEntity do
  @moduledoc false

  use Vex.Validator
  alias Core.Headers

  @il_microservice Application.get_env(:core, :microservices)[:il]

  def validate(legal_entity_id, options) do
    headers = [
      {String.to_atom(Headers.consumer_metadata()), Jason.encode!(%{"client_id" => legal_entity_id})}
    ]

    ets_key = "legal_entity_#{legal_entity_id}"

    case get_data(ets_key, legal_entity_id, headers) do
      {:ok, %{"data" => legal_entity}} ->
        :ets.insert(:message_cache, {ets_key, legal_entity})

        if Map.get(legal_entity, "status") == Keyword.get(options, :status) do
          :ok
        else
          error(options, Keyword.get(options, :messages)[:status])
        end

      _ ->
        error(options, "LegalEntity with such ID is not found")
    end
  end

  def error(options, error_message) do
    {:error, message(options, error_message)}
  end

  defp get_data(ets_key, legal_entity_id, headers) do
    case :ets.lookup(:message_cache, ets_key) do
      [{^ets_key, legal_entity}] -> {:ok, %{"data" => legal_entity}}
      _ -> @il_microservice.get_legal_entity(legal_entity_id, headers)
    end
  end
end
