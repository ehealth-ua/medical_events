defmodule Core.Expectations.DigitalSignature do
  @moduledoc false

  import Core.Microservices
  import Mox

  def signature do
    expect(DigitalSignatureMock, :decode, fn content, _ ->
      {:ok, decoded_content} = decode_response(Base.decode64!(content))

      {:ok,
       %{
         "data" => %{
           "content" => decoded_content,
           "signatures" => [%{"is_valid" => true, "signer" => %{}}]
         }
       }}
    end)
  end
end
