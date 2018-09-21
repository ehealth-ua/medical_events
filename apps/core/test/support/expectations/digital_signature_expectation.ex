defmodule Core.Expectations.DigitalSignatureExpectation do
  @moduledoc false

  import Core.Microservices
  import Mox

  def expect_signature do
    expect(DigitalSignatureMock, :decode, fn content, headers ->
      {:ok, decoded_content} = decode_response(Base.decode64!(content))

      {:ok,
       %{
         "data" => %{
           "content" => decoded_content,
           "signatures" => [
             %{
               "is_valid" => true,
               "signer" => %{
                 "drfo" => Core.Headers.get_header(headers, "drfo")
               }
             }
           ]
         }
       }}
    end)
  end
end
