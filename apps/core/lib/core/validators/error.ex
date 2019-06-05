defmodule Core.ValidationError do
  @moduledoc """
  Error struct and processing
  """

  @enforce_keys [:description, :path]
  defstruct description: nil, params: [], rule: :invalid, path: nil

  def error(options, default_message) do
    {:error, Keyword.get(options, :message, default_message)}
  end
end

defprotocol Core.Validators.Error do
  @doc "Dump error to tuple"
  def dump(error)
end

defimpl Core.Validators.Error, for: List do
  def dump(errors) do
    {:error,
     errors
     |> Enum.map(&Core.Validators.Error.dump/1)
     |> Enum.map(fn {_k, v} -> v end)
     |> Enum.flat_map(& &1)}
  end
end

defimpl Core.Validators.Error, for: Core.ValidationError do
  def dump(%{description: description, rule: rule, path: path, params: params}) do
    {:error,
     [
       {%{
          description: description,
          params: params,
          rule: rule
        }, path}
     ]}
  end
end
