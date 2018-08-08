defmodule Core.Kafka.ConsumerTest do
  @moduledoc false

  use Core.ModelCase

  alias Core.Kafka.Consumer
  alias Core.Mongo
  alias Core.Request
  alias Core.Requests
  alias Core.Requests.VisitCreateRequest
  import Mox
  import Core.Expectations.DigitalSignature

  @status_processed Request.status(:processed)

  describe "consume create visit event" do
    test "empty content" do
      expect(IlMock, :get_dictionaries, fn _, _ ->
        {:ok, %{"data" => %{}}}
      end)

      request = build(:request)
      assert {:ok, _} = Mongo.insert_one(request)
      signature()
      assert :ok = Consumer.consume(%VisitCreateRequest{_id: request._id, signed_data: [Base.encode64("")]})
      assert {:ok, %Request{status: @status_processed, response_size: 395}} = Requests.get_by_id(request._id)
    end

    test "empty map" do
      expect(IlMock, :get_dictionaries, fn _, _ ->
        {:ok, %{"data" => %{}}}
      end)

      request = build(:request)
      assert {:ok, _} = Mongo.insert_one(request)
      signature()

      assert :ok =
               Consumer.consume(%VisitCreateRequest{_id: request._id, signed_data: [Base.encode64(Jason.encode!(%{}))]})

      assert {:ok, %Request{status: @status_processed, response_size: 581}} = Requests.get_by_id(request._id)
    end

    test "success create visit" do
      expect(IlMock, :get_dictionaries, fn _, _ ->
        {:ok, %{"data" => %{}}}
      end)

      request = build(:request)
      assert {:ok, _} = Core.Mongo.insert_one(request)
      signature()
      signed_content = %{"encounters" => [], "conditions" => []}

      assert :ok =
               Consumer.consume(%VisitCreateRequest{
                 _id: request._id,
                 signed_data: [Base.encode64(Jason.encode!(signed_content))]
               })
    end
  end
end
