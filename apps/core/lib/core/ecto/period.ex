defmodule Core.Period do
  @moduledoc false

  use Core.Schema

  @derive Jason.Encoder

  defstruct [:start, :end]
end
