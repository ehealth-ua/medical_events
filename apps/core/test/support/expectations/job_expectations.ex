defmodule Core.Expectations.JobExpectations do
  @moduledoc false

  import Mox

  def expect_job_update(id, response, code) do
    id = to_string(id)

    expect(KafkaMock, :publish_job_update_status_event, fn event ->
      case event do
        %Core.Jobs.JobUpdateStatusJob{_id: ^id, response: ^response, status_code: ^code} ->
          :ok

        _ ->
          IO.inspect(event)
          raise ExUnit.AssertionError
      end
    end)
  end
end
