defmodule Core.Kafka.ConsumerTest do
  @moduledoc false

  use Core.ModelCase

  alias Core.Jobs.PackageCancelJob
  alias Core.Kafka.Consumer

  import Mox

  setup :verify_on_exit!

  describe "consume cancel package event" do
    test "microservices error" do
      expect(KafkaMock, :publish_medical_event, 1, fn _ -> :ok end)
      expect(DigitalSignatureMock, :decode, fn _, _ -> raise Core.Microservices.Error end)

      job = insert(:job)
      assert :ok = Consumer.consume(%PackageCancelJob{_id: to_string(job._id), signed_data: ""})
    end
  end
end
