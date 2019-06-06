defmodule Core.Expectations.DigitalSignatureExpectation do
  @moduledoc false

  import Mox

  def expect_signature(drfo) do
    expect(WorkerMock, :run, fn "ds_api", API.Rpc, :decode_signed_content, [content] ->
      decoded_content =
        content
        |> Base.decode64!()
        |> Jason.decode!()

      {:ok,
       %{
         content: decoded_content,
         signatures: [
           %{
             "is_valid" => true,
             "signer" => %{"drfo" => drfo}
           }
         ]
       }}
    end)
  end
end
