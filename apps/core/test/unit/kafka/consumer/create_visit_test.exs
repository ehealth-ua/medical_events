defmodule Core.Kafka.Consumer.CreateVisitTest do
  @moduledoc false

  use Core.ModelCase

  alias Core.Kafka.Consumer
  alias Core.Job
  alias Core.Jobs
  alias Core.Jobs.VisitCreateJob
  import Mox
  import Core.Expectations.DigitalSignature

  @status_processed Job.status(:processed)

  describe "consume create visit event" do
    test "empty content" do
      stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)

      expect(IlMock, :get_dictionaries, fn _, _ ->
        {:ok, %{"data" => %{}}}
      end)

      job = insert(:job)
      signature()
      assert :ok = Consumer.consume(%VisitCreateJob{_id: job._id, signed_data: [Base.encode64("")]})
      assert {:ok, %Job{status: @status_processed, response_size: 395}} = Jobs.get_by_id(job._id)
    end

    test "empty map" do
      stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)

      expect(IlMock, :get_dictionaries, fn _, _ ->
        {:ok, %{"data" => %{}}}
      end)

      job = insert(:job)
      signature()

      assert :ok = Consumer.consume(%VisitCreateJob{_id: job._id, signed_data: [Base.encode64(Jason.encode!(%{}))]})

      assert {:ok, %Job{status: @status_processed, response_size: 581}} = Jobs.get_by_id(job._id)
    end

    test "success create visit" do
      stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)

      expect(IlMock, :get_dictionaries, fn _, _ ->
        {:ok, %{"data" => %{}}}
      end)

      job = insert(:job)
      signature()
      signed_content = %{"encounters" => [], "conditions" => []}

      assert :ok =
               Consumer.consume(%VisitCreateJob{
                 _id: job._id,
                 signed_data: [Base.encode64(Jason.encode!(signed_content))]
               })

      assert {:ok,
              %Core.Job{
                response_size: 585,
                status: 1
              }} = Jobs.get_by_id(job._id)
    end
  end
end
