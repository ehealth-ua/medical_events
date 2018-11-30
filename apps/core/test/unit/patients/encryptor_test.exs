defmodule Core.Patients.EncryptorTest do
  @moduledoc false

  use ExUnit.Case
  alias Core.Patients.Encryptor

  test "encrypt, decrypt" do
    id = UUID.uuid4()
    hash = Encryptor.encrypt(id)
    assert 64 == String.length(hash)
    assert id == Encryptor.decrypt(hash)
  end
end
