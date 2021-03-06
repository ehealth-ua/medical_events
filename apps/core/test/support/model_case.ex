defmodule Core.ModelCase do
  @moduledoc """
  This module defines the test case to be used by
  tests that require setting up a connection.

  Such tests rely on `Phoenix.ConnTest` and also
  import other functionality to make it easier
  to build common datastructures and query the data layer.

  Finally, if the test case interacts with the database,
  it cannot be async. For this reason, every test runs
  inside a transaction which is reset at the beginning
  of the test unless the test case is marked as async.
  """

  use ExUnit.CaseTemplate, async: true

  using do
    quote do
      import Core.Expectations.IlExpectations
      import Core.Expectations.JobExpectations
      import Core.Factories
      alias Core.Mongo
    end
  end
end
