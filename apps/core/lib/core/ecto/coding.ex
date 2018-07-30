defmodule Core.Coding do
  @moduledoc false

  use Ecto.Schema

  @primary_key false
  embedded_schema do
    field(:system)
    field(:version)
    field(:code)
    field(:display)
  end
end
