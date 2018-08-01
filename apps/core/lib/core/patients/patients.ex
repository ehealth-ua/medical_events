defmodule Core.Patients do
  @moduledoc false

  alias Core.Validators.JsonSchema

  def create_visit(params) do
    with :ok <- JsonSchema.validate(:visit_create, params) do
      IO.inspect(params)
    end
  end
end
