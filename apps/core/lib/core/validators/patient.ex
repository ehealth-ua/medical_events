defmodule Core.Validators.Patient do
  @moduledoc false

  alias Core.Patient

  @status_active Patient.status(:active)

  def is_active(@status_active), do: :ok
  def is_active(_), do: {:error, {:conflict, "Person is not active"}}
end
