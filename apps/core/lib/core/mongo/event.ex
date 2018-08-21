defmodule Core.Mongo.Event do
  @moduledoc """
  MongoDB event for audit log
  """

  alias BSON.ObjectId
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
       when type in @allowed_event_types and is_binary(collection) and is_binary(actor_id),
       do: {:ok, event}

  defp validate(_event), do: {:error, :invalid_event_params}

  defp defaults({:ok, event}), do: {:ok, %{event | inserted_at: DateTime.utc_now()}}
  defp defaults(err), do: err
end
