defmodule Core.Period do
  @moduledoc false

  use Core.Schema

  embedded_schema do
    field(:start, presence: true)
    field(:end)
  end
end
