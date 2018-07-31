defmodule Core.Immunization do
  @moduledoc false

  use Core.Schema

  defstruct [:inserted_at, :updated_at, :inserted_by, :updated_by]

  # embedded_schema do
  #   timestamps()
  # end
end
