defmodule NumberGenerator.Generator do
  @moduledoc false

  use Confex, otp_app: :number_generator
  alias Core.Mongo
  alias Core.Mongo.Transaction
  alias Core.Number

  @alphabet "0123456789"
  @collection Number.metadata().collection

  def generate(entity_type, entity_id, actor_id) do
    case Mongo.find_one(@collection, %{"_id" => Mongo.string_to_uuid(entity_id)}) do
      nil ->
        do_generate(entity_type, entity_id, actor_id, "")

      %{"number" => number} ->
        number
    end
  end

  defp do_generate(entity_type, entity_id, actor_id, salt) do
    number = hash_entity_id(entity_id, salt)

    case Mongo.find_one(@collection, %{"entity_type" => entity_type, "number" => number}) do
      nil ->
        document = %Number{
          _id: Mongo.string_to_uuid(entity_id),
          entity_type: entity_type,
          number: number,
          inserted_by: Mongo.string_to_uuid(actor_id)
        }

        insert_result =
          %Transaction{actor_id: actor_id}
          |> Transaction.add_operation(@collection, :insert, Mongo.prepare_doc(document), entity_id)
          |> Transaction.flush()

        case insert_result do
          :ok -> number
          # Number was already generated for this entity_id
          {:error, _} -> generate(entity_type, entity_id, actor_id)
        end

      %{} ->
        do_generate(entity_type, entity_id, actor_id, UUID.uuid4())
    end
  end

  def hash_entity_id(entity_id, salt) do
    blake = Blake2.hash2b(entity_id <> salt, 16, config()[:key])
    base = String.length(@alphabet)

    {hash, ""} =
      Enum.reduce(0..(byte_size(blake) - 1), {"", blake}, fn _, {hash, acc} ->
        <<a, rest::binary>> = acc
        {hash <> String.at(@alphabet, rem(a, base)), rest}
      end)

    slices = for <<x::binary-4 <- hash>>, do: x
    Enum.join(slices, "-")
  end
end
