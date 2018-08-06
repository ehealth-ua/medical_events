defmodule Core.Kafka.ConsumerTest do
  @moduledoc false

  use Core.ModelCase

  alias Core.Kafka.Consumer
  alias Core.Requests.VisitCreateRequest
  import Mox

  describe "consume create visit event" do
    test "success consume visit event" do
      request = build(:request)
      assert {:ok, _} = Core.Mongo.insert_one(request)

      expect(DigitalSignatureMock, :decode, fn content, _ ->
        {:ok,
         %{"data" => %{"content" => Base.decode64!(content), "signatures" => [%{"is_valid" => true, "signer" => %{}}]}}}
      end)

      Consumer.consume(%VisitCreateRequest{id: request._id, signed_data: Base.encode64("")})
    end
  end
end
