# defmodule Core.Factories.Patient do
#   @moduledoc false

#   alias Ecto.UUID
#   alias Core.Schema.Patient
#   alias Core.Schema.Visit
#   require Triton.Query
#   import Core.FactoryPersister

#   defmacro __using__(_) do
#     quote do
#       def save_patient_factory(params \\ []) do
#         params
#         |> patient_factory()
#         |> Patient.save()
#       end

#       def patient_factory(params \\ []) do
#         now = :os.system_time(:millisecond)
#         id = UUID.generate()
#         visit_id = UUID.generate()

#         save(
#           Patient,
#           Keyword.merge(
#             [
#               person_id: id,
#               inserted_by: id,
#               updated_by: id,
#               inserted_at: now,
#               updated_at: now
#               # Jason.encode!(build(:visit))
#               # visits: "{'#{visit_id}': {start:#{now}, end:#{now}}}"
#               # Map.put(%{}, visit_id, %{
#               #   # inserted_at: to_string(DateTime.utc_now()),
#               #   # updated_at: to_string(DateTime.utc_now()),
#               #   # inserted_by: id,
#               #   # updated_by: id,
#               #   # period: %{
#               #   start: to_string(DateTime.utc_now()),
#               #   end: to_string(DateTime.utc_now())
#               #   # }
#               # })
#               # |> Jason.encode!()
#               # "{'#{visit_id}': {'inserted_at': #{now}, 'updated_at': #{now}, 'inserted_by': '#{id}', 'updated_by': '#{
#               #   id
#               # }', 'period': {'start': #{now}, 'end': #{now}}}]"
#               # episodes: build_list(3, :episode),
#             ],
#             params
#           )
#         )
#       end

#       def visit_factory(params \\ []) do
#         now = :os.system_time(:millisecond)
#         by = UUID.generate()

#         fields =
#           Keyword.merge(
#             [
#               id: UUID.generate(),
#               inserted_at: now,
#               updated_at: now,
#               inserted_by: by,
#               updated_by: by
#               # period: build(:period)
#             ],
#             params
#           )
#           |> Enum.into(%{})

#         # struct(Visit, fields)
#       end
#     end
#   end
# end
