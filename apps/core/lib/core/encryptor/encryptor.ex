defmodule Core.Encryptor do
  @moduledoc false

  use Confex, otp_app: :core

  @aes_block_size 16

  def encrypt(nil), do: nil

  def encrypt(data) when is_binary(data) do
    id =
      data
      |> UUID.string_to_binary!()
      |> pad(@aes_block_size)

    :aes_cbc128
    |> :crypto.block_encrypt(config()[:keyphrase], config()[:ivphrase], id)
    |> Base.encode16()
  rescue
    ArgumentError -> nil
  end

  def decrypt(data) do
    :aes_cbc128
    |> :crypto.block_decrypt(config()[:keyphrase], config()[:ivphrase], Base.decode16!(data))
    |> unpad()
    |> UUID.binary_to_string!()
  end

  def pad(data, block_size) do
    to_add = block_size - rem(byte_size(data), block_size)
    data <> to_string(:string.chars(to_add, to_add))
  end

  def unpad(data) do
    to_remove = :binary.last(data)
    :binary.part(data, 0, byte_size(data) - to_remove)
  end
end
