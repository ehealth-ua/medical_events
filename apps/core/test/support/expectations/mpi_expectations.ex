defmodule Core.Expectations.MPIExpectations do
  @moduledoc false

  import Mox

  def expect_person(id, n \\ 1) do
    expect(MPIMock, :person, n, fn _id, _headers ->
      {:ok,
       %{
         "data" => %{
           "id" => id,
           "first_name" => "Алекс",
           "last_name" => "Джонс",
           "second_name" => "Петрович",
           "tax_id" => "2222222220",
           "authentication_methods" => [
             %{
               "type" => "OTP",
               "phone_number" => "+38#{Enum.random(1_000_000_000..9_999_999_999)}"
             },
             %{
               "type" => Enum.random(["OTP", "OFFLINE"]),
               "phone_number" => "+38#{Enum.random(1_000_000_000..9_999_999_999)}"
             }
           ]
         }
       }}
    end)
  end

  def expect_person_offline_auth_method(id, n \\ 1) do
    expect(MPIMock, :person, n, fn _id, _headers ->
      {:ok,
       %{
         "data" => %{
           "id" => id,
           "first_name" => "Алекс",
           "last_name" => "Джонс",
           "second_name" => "Петрович",
           "tax_id" => "2222222220",
           "authentication_methods" => [
             %{
               "type" => "OFFLINE",
               "phone_number" => nil
             }
           ]
         }
       }}
    end)
  end
end
