defmodule Core.Mongo.Event do
  @moduledoc """
  MongoDB event for audit log
  """

  alias BSON.ObjectId
  alias __MODULE__

  @allowed_event_types ~w(INSERT UPDATE DELETE)
  @enforce_keys ~w(type entry_id collection)a
  defstruct ~w(type entry_id collection params filter)a

  def new(params) when is_map(params) do
    Event
    |> struct(params)
    |> validate()
  end

  defp validate(%{type: type, collection: collection} = event)
       when type in @allowed_event_types and is_binary(collection),
       do: {:ok, event}

  defp validate(_event), do: {:error, :invalid_event_params}
end
