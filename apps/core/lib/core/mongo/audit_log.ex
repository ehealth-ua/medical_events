defmodule Core.Mongo.AuditLog do
  @moduledoc false

  alias Core.Mongo.Event
  alias DBConnection.Poolboy
  alias Mongo.DeleteResult
  alias Mongo.Error
  alias Mongo.InsertOneResult
  alias Mongo.UpdateResult
  require Logger

  @kafka_producer Application.get_env(:core, :kafka)[:producer]

  @insert "INSERT"
  @update "UPDATE"
  @delete "DELETE"

  @collection_audit_log "audit_log"
  @collections_blacklist ~w(schema_migrations jobs)

  @audit_operations %{
    # insert
    insert_one: @insert,
    insert_one!: @insert,
    # update
    replace_one: @update,
    replace_one!: @update,
    update_one: @update,
    update_one!: @update,
    find_one_and_replace: @update,
    find_one_and_update: @update,
    # delete
    delete_one: @delete,
    delete_one!: @delete,
    find_one_and_delete: @delete
  }

  @audit_operation_keys Map.keys(@audit_operations)

  defguard result_success(result) when result in [DeleteResult, InsertOneResult, UpdateResult]
  defguard is_collection_blacklisted(collection) when collection not in @collections_blacklist
  defguard is_operation_whitelisted(operation) when operation in @audit_operation_keys

  @doc """
  Prepare and push MongoDB INSERT, UPDATE and DELETE operations into Kafka for audit log.
  List of audited operations defined in `@audit_operations`

  All CRUD operations in @collections_blacklist ignored
  """
  def log_operation({:ok, nil} = operation_result, _operation, _args), do: operation_result

  def log_operation({:ok, result} = operation_result, operation, [collection | _] = args)
      when is_collection_blacklisted(collection) and is_operation_whitelisted(operation) do
    push_event_to_log(result, operation, collection, args)
    operation_result
  end

  def log_operation(%{__struct__: result} = operation_result, operation, [collection | _] = args)
      when is_collection_blacklisted(collection) and is_operation_whitelisted(operation) and result_success(result) do
    push_event_to_log(operation_result, operation, collection, args)
    operation_result
  end

  def log_operation(operation_result, _operation, _args), do: operation_result

  defp push_event_to_log(operation_result, operation, collection, args) do
    with {:ok, map_event} <- prepare_event(operation_result, operation, args) do
      actor_id = fetch_actor_id(map_event.params, List.last(args))

      {:ok, event} =
        map_event
        |> Map.merge(%{collection: collection, actor_id: actor_id})
        |> Event.new()

      unless @kafka_producer.publish_mongo_event(event) == :ok do
        Logger.error(
          "Failed to publish audit log to Kafka. Push data: operation: `#{operation}`, id: `#{map_event.entry_id}`," <>
            "collection: `#{collection}`, params: `#{inspect(map_event.params)}`"
        )
      end
    end
  end

  defp prepare_event(%DeleteResult{deleted_count: 0}, _, _), do: :skip_audit_log

  defp prepare_event(%DeleteResult{}, _operation, args) do
    {params, filter} = fetch_event_data(@delete, args)

    {:ok,
     %{
       type: @delete,
       params: params,
       filter: filter,
       entry_id: filter["_id"]
     }}
  end

  defp prepare_event(%InsertOneResult{inserted_id: nil}, _operation, _args), do: :skip_audit_log

  defp prepare_event(%InsertOneResult{inserted_id: entry_id}, _operation, args) do
    {params, filter} = fetch_event_data(@insert, args)

    {:ok,
     %{
       type: @insert,
       params: params,
       filter: filter,
       entry_id: entry_id
     }}
  end

  defp prepare_event(%UpdateResult{modified_count: 0}, _, _), do: :skip_audit_log

  defp prepare_event(%UpdateResult{matched_count: 0, modified_count: count}, _operation, args) when count > 0 do
    {params, filter} = fetch_event_data(@update, args)

    {:ok,
     %{
       type: @insert,
       params: params,
       filter: filter,
       entry_id: filter["_id"]
     }}
  end

  defp prepare_event(%UpdateResult{modified_count: count}, _operation, args) when count > 0 do
    {params, filter} = fetch_event_data(@update, args)

    {:ok,
     %{
       type: @update,
       params: params,
       filter: filter,
       entry_id: filter["_id"]
     }}
  end

  # for find_one_and_update, find_one_and_replace and find_one_and_delete operations
  defp prepare_event(result, operation, args) when is_map(result) do
    operation_type = @audit_operations[operation]
    {params, filter} = fetch_event_data(operation_type, args)

    {:ok,
     %{
       type: operation_type,
       params: params,
       filter: filter,
       entry_id: filter["_id"]
     }}
  end

  defp fetch_event_data(@insert, [_, params | _]), do: {params, nil}
  defp fetch_event_data(@delete, [_, filter | _]), do: {nil, filter}
  defp fetch_event_data(@update, [_, filter, params | _]), do: {params, filter}

  # fetch from data set. Usually for insert operations
  defp fetch_actor_id(%{updated_by: actor_id}, _opts), do: actor_id
  defp fetch_actor_id(%{"updated_by" => actor_id}, _opts), do: actor_id

  # fetch from $set attribute. Usually for update operations
  defp fetch_actor_id(%{"$set" => %{updated_by: actor_id}}, _opts), do: actor_id
  defp fetch_actor_id(%{"$set" => %{"updated_by" => actor_id}}, _opts), do: actor_id

  # fetch from data set. Usually for replace or delete operations
  defp fetch_actor_id(_params, actor_id: actor_id), do: actor_id
  defp fetch_actor_id(_, _), do: nil

  @doc """
  Insert MongoDB operation log into audit_log collection
  """
  def store_event(%Event{} = event) do
    case Mongo.insert_one(:mongo_audit_log, @collection_audit_log, Map.from_struct(event), pool: Poolboy) do
      {:ok, _} ->
        :ok

      {:error, %Error{} = err} ->
        Logger.error("Failed to store event in MongoDB audit log. Reason: `#{err.message}`, code: `#{err.code}`")

      err ->
        Logger.error("Failed to store event in MongoDB audit log. Error: `#{inspect(err)}")
    end
  end

  def collection, do: @collection_audit_log
end
