defmodule Core.Redis do
  @moduledoc false

  use Confex, otp_app: :core

  def command(command) do
    Redix.command(:"redix_#{random_index()}", command)
  end

  def setnx(key, value) do
    command(["SETNX", key, value])
  end

  def setex(key, value, ttl) do
    command(["SETEX", key, ttl, value])
  end

  defp random_index do
    rem(System.unique_integer([:positive]), config()[:pool_size])
  end
end
