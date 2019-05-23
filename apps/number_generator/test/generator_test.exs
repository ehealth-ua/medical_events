defmodule NumberGenerator.GeneratorTest do
  @moduledoc false

  use ExUnit.Case
  alias NumberGenerator.Generator
  import Core.Factories
  import Mox

  describe "test generate" do
    test "success generate" do
      entity_type = "episode_id"
      entity_id = UUID.uuid4()
      actor_id = UUID.uuid4()

      expect(WorkerMock, :run, fn _, _, :transaction, args ->
        assert %{
                 "actor_id" => ^actor_id,
                 "operations" => [%{"collection" => "numbers", "operation" => "insert"}]
               } = Jason.decode!(args)

        :ok
      end)

      assert number = Generator.generate(entity_type, entity_id, actor_id)
    end

    test "number already exists" do
      entity_id = UUID.uuid4()
      hash = Generator.hash_entity_id(entity_id, "")
      number = insert(:number, _id: entity_id, number: hash)
      actor_id = number.inserted_by

      expect(WorkerMock, :run, fn _, _, :transaction, args ->
        assert %{
                 "actor_id" => ^actor_id,
                 "operations" => [%{"collection" => "numbers", "operation" => "insert"}]
               } = Jason.decode!(args)

        :ok
      end)

      assert Generator.generate(number.entity_type, number._id, actor_id)
    end
  end
end
