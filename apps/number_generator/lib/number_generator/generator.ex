defmodule NumberGenerator.Generator do
  @moduledoc false

  use Confex, otp_app: :number_generator
  alias Core.Mongo
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
    blake = Blake2.hash2b(entity_id <> salt, 16, config()[:key])
    base = String.length(@alphabet)

    {hash, ""} =
      Enum.reduce(0..(byte_size(blake) - 1), {"", blake}, fn _, {hash, acc} ->
        <<a, rest::binary>> = acc
        {hash <> String.at(@alphabet, rem(a, base)), rest}
      end)

    slices = for <<x::binary-4 <- hash>>, do: x
    number = Enum.join(slices, "-")

    case Mongo.find_one(@collection, %{"entity_type" => entity_type, "number" => number}) do
      nil ->
        insert_result =
          Mongo.insert_one(%Number{
            _id: Mongo.string_to_uuid(entity_id),
            entity_type: entity_type,
            number: number,
            inserted_by: Mongo.string_to_uuid(actor_id)
          })

        case insert_result do
          {:ok, %{inserted_id: _id}} -> number
          # Number was already generated for this entity_id
          {:error, %{code: 11_000}} -> generate(entity_type, entity_id, actor_id)
        end

      %{} ->
        do_generate(entity_type, entity_id, actor_id, UUID.uuid4())
    end
  end
end
