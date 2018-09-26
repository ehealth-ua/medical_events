Application.put_env(:core, Core.Patients, pk_hash_salt: "test_salt")
{:ok, _} = Application.ensure_all_started(:ex_machina)
ExUnit.start()
ExUnit.configure(exclude: [pending: true])
