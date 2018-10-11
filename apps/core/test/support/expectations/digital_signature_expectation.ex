defmodule Core.Expectations.DigitalSignatureExpectation do
  @moduledoc false

  import Core.Microservices
  import Mox

  def expect_signature(drfo) do
    expect(DigitalSignatureMock, :decode, fn content, _headers ->
      {:ok, decoded_content} = decode_response(Base.decode64!(content))

      {:ok,
       %{
         "data" => %{
           "content" => decoded_content,
           "signatures" => [
             %{
               "is_valid" => true,
               "signer" => %{"drfo" => drfo}
             }
           ]
         }
       }}
    end)
  end
end
