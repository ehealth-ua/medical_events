defmodule Core.Search do
  @moduledoc false

  def add_param(search_params, value, path, operator \\ "$eq")
  def add_param(search_params, nil, _path, _operator), do: search_params
  def add_param(search_params, [], _path, _operator), do: search_params

  def add_param(search_params, %Date{} = value, path, operator) do
    do_add_param(search_params, value, path, operator)
  end

  def add_param(search_params, %DateTime{} = value, path, operator) do
    do_add_param(search_params, value, path, operator)
  end

  def add_param(search_params, %BSON.Binary{} = value, path, operator) do
    do_add_param(search_params, value, path, operator)
  end

  def add_param(search_params, value, path, operator) when is_map(value) do
    value
    |> Enum.reject(fn {_, v} -> is_nil(v) end)
    |> Enum.into(%{})
    |> Map.keys()
    |> case do
      [] -> search_params
      _ -> do_add_param(search_params, value, path, operator)
    end
  end

  def add_param(search_params, value, path, operator) do
    do_add_param(search_params, value, path, operator)
  end

  def do_add_param(search_params, value, path, operator) do
    if get_in(search_params, path) == nil do
      put_in(search_params, path, %{operator => value})
    else
      update_in(search_params, path, &Map.merge(&1, %{operator => value}))
    end
  end
end
