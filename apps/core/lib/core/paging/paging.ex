defmodule Core.Paging do
  @moduledoc false

  alias Core.Mongo
  alias Scrivener.Page

  def create do
    %Page{
      entries: [],
      page_number: 1,
      page_size: 50,
      total_entries: 0,
      total_pages: 0
    }
  end

  def paginate(:aggregate, collection, pipeline, paging) do
    [page_number: page_number, limit: page_size, offset: offset] = page_options(paging)
    paging_pipeline = pipeline ++ [%{"$skip" => offset}, %{"$limit" => page_size}]
    count_pipeline = pipeline ++ [%{"$count" => "total"}]

    count = aggregate_collection(collection, count_pipeline)
    enities = aggregate_collection(collection, paging_pipeline)

    %{
      total_pages: total_pages,
      total_entries: total_entries
    } = paging(page_number, page_size, count)

    %Page{
      entries: enities,
      page_number: page_number,
      page_size: page_size,
      total_entries: total_entries,
      total_pages: total_pages
    }
  end

  def page_options(params) do
    page_number = get_page_param_option(Map.get(params, "page"), 1)
    page_size = get_page_param_option(Map.get(params, "page_size"), 50)
    offset = if page_number > 0, do: (page_number - 1) * page_size, else: 0
    [page_number: page_number, limit: page_size, offset: offset]
  end

  defp paging(page, page_size, total) do
    total =
      case total do
        [%{"total" => total}] -> total
        _ -> 0
      end

    total_pages = trunc(Float.ceil(total / page_size))

    %{
      total_pages: total_pages,
      total_entries: total,
      page_size: page_size,
      page_number: page
    }
  end

  defp get_page_param_option(nil, default), do: default
  defp get_page_param_option(n, _) when is_integer(n), do: n

  defp get_page_param_option(text, default) when is_binary(text) do
    case Integer.parse(text) do
      {n, _} ->
        n

      :error ->
        default
    end
  end

  defp aggregate_collection(collection, pipeline) do
    collection
    |> Mongo.aggregate(pipeline)
    |> Enum.to_list()
  end
end
