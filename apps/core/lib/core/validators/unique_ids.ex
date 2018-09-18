defmodule Core.Validators.UniqueIds do
  @moduledoc false

  use Vex.Validator

  def validate(values, options) do
    id_field = Keyword.get(options, :field)
    ids = Enum.map(values, &Map.get(&1, id_field))

    if Enum.uniq(ids) == ids do
      :ok
    else
      error(options, "All primary keys must be unique")
    end
  end

  def error(options, error_message) do
    {:error, message(options, error_message)}
  end
end
