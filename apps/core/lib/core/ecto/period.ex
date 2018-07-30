defmodule Core.Period do
  @moduledoc false

  use Ecto.Schema

  @primary_key false
  embedded_schema do
    field(:start, :naive_datetime)
    field(:end, :naive_datetime)
  end
end
