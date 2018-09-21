defmodule Core.Mongo.Event do
  @moduledoc """
  MongoDB event for audit log
  """

  alias __MODULE__

  @allowed_event_types ~w(INSERT UPDATE DELETE)
  @enforce_keys ~w(type entry_id collection actor_id)a
  defstruct ~w(type entry_id collection params filter actor_id inserted_at)a

  def new(params) when is_map(params) do
    Event
    |> struct(params)
    |> validate()
    |> defaults()
  end

  defp validate(%{type: type, collection: collection, actor_id: actor_id} = event)
       when type in @allowed_event_types and is_binary(collection) do
    case actor_id do
      %BSON.Binary{subtype: :uuid} -> {:ok, event}
      value when is_binary(value) -> {:ok, event}
      _ -> {:error, :invalid_event_params}
    end
  end

  defp validate(_event), do: {:error, :invalid_event_params}

  defp defaults({:ok, event}), do: {:ok, %{event | inserted_at: DateTime.utc_now()}}
  defp defaults(err), do: err
end
