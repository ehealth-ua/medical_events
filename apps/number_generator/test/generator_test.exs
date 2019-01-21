defmodule NumberGenerator.GeneratorTest do
  @moduledoc false

  use ExUnit.Case
  alias NumberGenerator.Generator
  import Mox

  describe "test generate" do
    test "success generate" do
      stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)
      entity_type = "episode_id"
      entity_id = UUID.uuid4()
      actor_id = UUID.uuid4()

      assert number = Generator.generate(entity_type, entity_id, actor_id)
      assert ^number = Generator.generate(entity_type, entity_id, actor_id)
    end
  end
end
