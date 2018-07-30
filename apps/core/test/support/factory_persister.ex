defmodule Core.FactoryPersister do
  @moduledoc false

  require Triton.Query
  import Triton.Query

  def save(type, params) do
    insert(type, params)
  end
end
