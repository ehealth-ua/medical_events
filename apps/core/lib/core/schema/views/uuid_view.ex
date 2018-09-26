defmodule Core.UUIDView do
  @moduledoc false

  def render(%BSON.Binary{binary: binary, subtype: :uuid}) do
    UUID.binary_to_string!(binary)
  end

  def render(value), do: value
end
