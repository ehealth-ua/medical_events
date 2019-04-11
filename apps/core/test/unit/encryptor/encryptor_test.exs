defmodule Core.EncryptorTest do
  @moduledoc false

  use ExUnit.Case
  alias Core.Encryptor

  test "encrypt, decrypt UUID" do
    id = UUID.uuid4()
    hash = Encryptor.encrypt(id)
    assert 64 == String.length(hash)
    assert id == Encryptor.decrypt(hash)
  end

  test "encrypt, decrypt binary" do
    id = "8056-7629-2664-3496"
    hash = Encryptor.encrypt(id)
    assert 64 == String.length(hash)
    assert id == Encryptor.decrypt(hash)
  end

  test "encrypt, decrypt nil" do
    id = nil
    hash = Encryptor.encrypt(id)
    assert id == Encryptor.decrypt(hash)
  end
end
