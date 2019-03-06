defmodule Core.OneOfValidationTest do
  @moduledoc """
  Test json oneOf validations defined in Core.Validators.OneOf
  """
  use ExUnit.Case

  alias Core.Validators.OneOf

  describe "json schema oneOf validations when oneOf objects are required" do
    test "success" do
      # one_of_params is map
      one_of_params = %{"$.level_2" => %{"params" => ["level_2_4", "level_2_5"], "required" => true}}
      assert :ok == OneOf.validate(get_params(), one_of_params)
      assert :ok == OneOf.validate(get_nested_params(), one_of_params)

      # one_of_params is list
      one_of_params = %{
        "$.level_2" => [
          %{"params" => ["level_2_4", "level_2_5"], "required" => true},
          %{"params" => ["level_2_4", "level_2_6"], "required" => true}
        ]
      }

      assert :ok == OneOf.validate(get_params(), one_of_params)
      assert :ok == OneOf.validate(get_nested_params(), one_of_params)
    end

    test "invalid request params: both oneOf parameters are sent" do
      # one_of_params is map
      one_of_params = %{"$.level_2" => %{"params" => ["level_2_3", "level_2_4"], "required" => true}}

      assert {:error,
              [
                {%{
                   description: "Only one of the parameters must be present",
                   params: ["$.level_2.level_2_3", "$.level_2.level_2_4"],
                   rule: "oneOf"
                 }, "$.level_2.level_2_3"},
                {%{
                   description: "Only one of the parameters must be present",
                   params: ["$.level_2.level_2_3", "$.level_2.level_2_4"],
                   rule: "oneOf"
                 }, "$.level_2.level_2_4"}
              ]} == OneOf.validate(get_params(), one_of_params)

      assert {:error,
              [
                {%{
                   description: "Only one of the parameters must be present",
                   params: ["$[0][0].level_2[0][0].level_2_3", "$[0][0].level_2[0][0].level_2_4"],
                   rule: "oneOf"
                 }, "$[0][0].level_2[0][0].level_2_3"},
                {%{
                   description: "Only one of the parameters must be present",
                   params: ["$[0][0].level_2[0][0].level_2_3", "$[0][0].level_2[0][0].level_2_4"],
                   rule: "oneOf"
                 }, "$[0][0].level_2[0][0].level_2_4"}
              ]} == OneOf.validate(get_nested_params(), one_of_params)

      # one_of_params is list
      one_of_params = %{
        "$.level_2" => [
          %{"params" => ["level_2_1", "level_2_2"], "required" => true},
          %{"params" => ["level_2_3", "level_2_4"], "required" => true}
        ]
      }

      assert {:error,
              [
                {%{
                   description: "Only one of the parameters must be present",
                   params: ["$.level_2.level_2_1", "$.level_2.level_2_2"],
                   rule: "oneOf"
                 }, "$.level_2.level_2_1"},
                {%{
                   description: "Only one of the parameters must be present",
                   params: ["$.level_2.level_2_1", "$.level_2.level_2_2"],
                   rule: "oneOf"
                 }, "$.level_2.level_2_2"},
                {%{
                   description: "Only one of the parameters must be present",
                   params: ["$.level_2.level_2_3", "$.level_2.level_2_4"],
                   rule: "oneOf"
                 }, "$.level_2.level_2_3"},
                {%{
                   description: "Only one of the parameters must be present",
                   params: ["$.level_2.level_2_3", "$.level_2.level_2_4"],
                   rule: "oneOf"
                 }, "$.level_2.level_2_4"}
              ]} == OneOf.validate(get_params(), one_of_params)

      assert {:error,
              [
                {%{
                   description: "Only one of the parameters must be present",
                   params: ["$[0][0].level_2[0][0].level_2_1", "$[0][0].level_2[0][0].level_2_2"],
                   rule: "oneOf"
                 }, "$[0][0].level_2[0][0].level_2_1"},
                {%{
                   description: "Only one of the parameters must be present",
                   params: ["$[0][0].level_2[0][0].level_2_1", "$[0][0].level_2[0][0].level_2_2"],
                   rule: "oneOf"
                 }, "$[0][0].level_2[0][0].level_2_2"},
                {%{
                   description: "Only one of the parameters must be present",
                   params: ["$[0][0].level_2[0][0].level_2_3", "$[0][0].level_2[0][0].level_2_4"],
                   rule: "oneOf"
                 }, "$[0][0].level_2[0][0].level_2_3"},
                {%{
                   description: "Only one of the parameters must be present",
                   params: ["$[0][0].level_2[0][0].level_2_3", "$[0][0].level_2[0][0].level_2_4"],
                   rule: "oneOf"
                 }, "$[0][0].level_2[0][0].level_2_4"}
              ]} == OneOf.validate(get_nested_params(), one_of_params)
    end

    test "invalid request params: none of the oneOf parameters are sent" do
      # one_of_params is map
      one_of_params = %{"$.level_2" => %{"params" => ["level_2_5", "level_2_6"], "required" => true}}

      assert {:error,
              [
                {%{
                   description: "At least one of the parameters must be present",
                   params: ["$.level_2.level_2_5", "$.level_2.level_2_6"],
                   rule: "oneOf"
                 }, "$.level_2"}
              ]} == OneOf.validate(get_params(), one_of_params)

      assert {:error,
              [
                {%{
                   description: "At least one of the parameters must be present",
                   params: ["$[0][0].level_2[0][0].level_2_5", "$[0][0].level_2[0][0].level_2_6"],
                   rule: "oneOf"
                 }, "$[0][0].level_2[0][0]"}
              ]} == OneOf.validate(get_nested_params(), one_of_params)

      # one_of_params is list
      one_of_params = %{
        "$.level_2" => [
          %{"params" => ["level_2_5", "level_2_6"], "required" => true},
          %{"params" => ["level_2_7", "level_2_8"], "required" => true}
        ]
      }

      assert {:error,
              [
                {%{
                   description: "At least one of the parameters must be present",
                   params: ["$.level_2.level_2_5", "$.level_2.level_2_6"],
                   rule: "oneOf"
                 }, "$.level_2"},
                {%{
                   description: "At least one of the parameters must be present",
                   params: ["$.level_2.level_2_7", "$.level_2.level_2_8"],
                   rule: "oneOf"
                 }, "$.level_2"}
              ]} == OneOf.validate(get_params(), one_of_params)

      assert {:error,
              [
                {%{
                   description: "At least one of the parameters must be present",
                   params: ["$[0][0].level_2[0][0].level_2_5", "$[0][0].level_2[0][0].level_2_6"],
                   rule: "oneOf"
                 }, "$[0][0].level_2[0][0]"},
                {%{
                   description: "At least one of the parameters must be present",
                   params: ["$[0][0].level_2[0][0].level_2_7", "$[0][0].level_2[0][0].level_2_8"],
                   rule: "oneOf"
                 }, "$[0][0].level_2[0][0]"}
              ]} == OneOf.validate(get_nested_params(), one_of_params)
    end
  end

  describe "json schema oneOf validations when oneOf objects are NOT required" do
    test "success when oneOf objects are sent" do
      # one_of_params is map
      one_of_params = %{"$.level_2" => %{"params" => ["level_2_4", "level_2_5"]}}
      assert :ok == OneOf.validate(get_params(), one_of_params)
      assert :ok == OneOf.validate(get_nested_params(), one_of_params)

      # one_of_params is list
      one_of_params = %{
        "$.level_2" => [%{"params" => ["level_2_4", "level_2_5"]}, %{"params" => ["level_2_4", "level_2_6"]}]
      }

      assert :ok == OneOf.validate(get_params(), one_of_params)
      assert :ok == OneOf.validate(get_nested_params(), one_of_params)
    end

    test "success when oneOf objects are not sent" do
      # one_of_params is map
      one_of_params = %{"$.level_2" => %{"params" => ["level_2_5", "level_2_6"], "required" => false}}
      assert :ok == OneOf.validate(get_params(), one_of_params)
      assert :ok == OneOf.validate(get_nested_params(), one_of_params)

      # one_of_params is list
      one_of_params = %{
        "$.level_2" => [
          %{"params" => ["level_2_5", "level_2_6"], "required" => false},
          %{"params" => ["test1", "test2"], "required" => false}
        ]
      }

      assert :ok == OneOf.validate(get_params(), one_of_params)
      assert :ok == OneOf.validate(get_nested_params(), one_of_params)
    end

    test "invalid request params: both oneOf parameters are sent" do
      # one_of_params is map
      one_of_params = %{"$.level_2" => %{"params" => ["level_2_3", "level_2_4"]}}

      assert {:error,
              [
                {%{
                   description: "Only one of the parameters must be present",
                   params: ["$.level_2.level_2_3", "$.level_2.level_2_4"],
                   rule: "oneOf"
                 }, "$.level_2.level_2_3"},
                {%{
                   description: "Only one of the parameters must be present",
                   params: ["$.level_2.level_2_3", "$.level_2.level_2_4"],
                   rule: "oneOf"
                 }, "$.level_2.level_2_4"}
              ]} == OneOf.validate(get_params(), one_of_params)

      assert {:error,
              [
                {%{
                   description: "Only one of the parameters must be present",
                   params: ["$[0][0].level_2[0][0].level_2_3", "$[0][0].level_2[0][0].level_2_4"],
                   rule: "oneOf"
                 }, "$[0][0].level_2[0][0].level_2_3"},
                {%{
                   description: "Only one of the parameters must be present",
                   params: ["$[0][0].level_2[0][0].level_2_3", "$[0][0].level_2[0][0].level_2_4"],
                   rule: "oneOf"
                 }, "$[0][0].level_2[0][0].level_2_4"}
              ]} == OneOf.validate(get_nested_params(), one_of_params)

      # one_of_params is list
      one_of_params = %{
        "$.level_2" => [%{"params" => ["level_2_1", "level_2_2"]}, %{"params" => ["level_2_3", "level_2_4"]}]
      }

      assert {:error,
              [
                {%{
                   description: "Only one of the parameters must be present",
                   params: ["$.level_2.level_2_1", "$.level_2.level_2_2"],
                   rule: "oneOf"
                 }, "$.level_2.level_2_1"},
                {%{
                   description: "Only one of the parameters must be present",
                   params: ["$.level_2.level_2_1", "$.level_2.level_2_2"],
                   rule: "oneOf"
                 }, "$.level_2.level_2_2"},
                {%{
                   description: "Only one of the parameters must be present",
                   params: ["$.level_2.level_2_3", "$.level_2.level_2_4"],
                   rule: "oneOf"
                 }, "$.level_2.level_2_3"},
                {%{
                   description: "Only one of the parameters must be present",
                   params: ["$.level_2.level_2_3", "$.level_2.level_2_4"],
                   rule: "oneOf"
                 }, "$.level_2.level_2_4"}
              ]} == OneOf.validate(get_params(), one_of_params)

      assert {:error,
              [
                {%{
                   description: "Only one of the parameters must be present",
                   params: ["$[0][0].level_2[0][0].level_2_1", "$[0][0].level_2[0][0].level_2_2"],
                   rule: "oneOf"
                 }, "$[0][0].level_2[0][0].level_2_1"},
                {%{
                   description: "Only one of the parameters must be present",
                   params: ["$[0][0].level_2[0][0].level_2_1", "$[0][0].level_2[0][0].level_2_2"],
                   rule: "oneOf"
                 }, "$[0][0].level_2[0][0].level_2_2"},
                {%{
                   description: "Only one of the parameters must be present",
                   params: ["$[0][0].level_2[0][0].level_2_3", "$[0][0].level_2[0][0].level_2_4"],
                   rule: "oneOf"
                 }, "$[0][0].level_2[0][0].level_2_3"},
                {%{
                   description: "Only one of the parameters must be present",
                   params: ["$[0][0].level_2[0][0].level_2_3", "$[0][0].level_2[0][0].level_2_4"],
                   rule: "oneOf"
                 }, "$[0][0].level_2[0][0].level_2_4"}
              ]} == OneOf.validate(get_nested_params(), one_of_params)
    end
  end

  describe "argument errors" do
    test "root symbol missed" do
      one_of_params = %{"level_2" => %{"params" => ["level_2_4", "level_2_5"], "required" => true}}
      assert_raise ArgumentError, fn -> OneOf.validate(get_params(), one_of_params) end
    end

    test "root symbol is not first in path" do
      # one_of_params is map
      one_of_params = %{"$.level_2.$.test" => %{"params" => ["level_2_4", "level_2_5"], "required" => true}}
      assert_raise ArgumentError, fn -> OneOf.validate(get_params(), one_of_params) end

      # one_of_params is list
      one_of_params = %{
        "$.level_2.$.test" => [
          %{"params" => ["level_2_4", "level_2_5"], "required" => true},
          %{"params" => ["level_2_4", "level_2_6"], "required" => true}
        ]
      }

      assert_raise ArgumentError, fn -> OneOf.validate(get_params(), one_of_params) end
    end

    test "params key missed" do
      # one_of_params is map
      one_of_params = %{"$.level_2" => %{"test" => ["level_2_4", "level_2_5"], "required" => true}}
      assert_raise ArgumentError, fn -> OneOf.validate(get_params(), one_of_params) end

      # one_of_params is list
      one_of_params = %{
        "$.level_2" => [
          %{"test1" => ["level_2_4", "level_2_5"], "required" => true},
          %{"test2" => ["level_2_4", "level_2_5"], "required" => true}
        ]
      }

      assert_raise ArgumentError, fn -> OneOf.validate(get_params(), one_of_params) end
    end

    test "invalid params type (not list)" do
      # one_of_params is map
      one_of_params = %{"$.level_2" => %{"params" => "level_2_4, level_2_5", "required" => true}}
      assert_raise ArgumentError, fn -> OneOf.validate(get_params(), one_of_params) end

      # one_of_params is list
      one_of_params = %{
        "$.level_2" => [
          %{"params" => ["level_2_4", "level_2_6"], "required" => true},
          %{"params" => "level_2_4, level_2_5", "required" => true}
        ]
      }

      assert_raise ArgumentError, fn -> OneOf.validate(get_params(), one_of_params) end
    end

    test "invalid path to params when strict_path_validation is true" do
      # one_of_params is map
      one_of_params = %{"$.test" => %{"params" => ["test_1", "test_2"], "required" => true}}
      assert_raise ArgumentError, fn -> OneOf.validate(get_params(), one_of_params, strict_path_validation: true) end

      # one_of_params is list
      one_of_params = %{
        "$.test" => [
          %{"params" => ["level_2_4", "level_2_6"], "required" => true},
          %{"params" => ["test_1", "test_2"], "required" => true}
        ]
      }

      assert_raise ArgumentError, fn -> OneOf.validate(get_params(), one_of_params, strict_path_validation: true) end
    end

    test "invalid path to params when strict_path_validation is false (by default)" do
      # one_of_params is map
      one_of_params = %{"$.test" => %{"params" => ["test_1", "test_2"], "required" => true}}
      assert :ok == OneOf.validate(get_params(), one_of_params)
      assert :ok == OneOf.validate(get_nested_params(), one_of_params)

      # one_of_params is list
      one_of_params = %{
        "$.test" => [
          %{"params" => ["level_2_4", "level_2_6"], "required" => true},
          %{"params" => ["test_1", "test_2"], "required" => true}
        ]
      }

      assert :ok == OneOf.validate(get_params(), one_of_params)
      assert :ok == OneOf.validate(get_nested_params(), one_of_params)
    end
  end

  defp get_params do
    %{
      "level_1" => %{
        "level_1_1" => "test",
        "level_1_2" => 0
      },
      "level_2" => %{
        "level_2_1" => "test",
        "level_2_2" => 0,
        "level_2_3" => "2017-01-01",
        "level_2_4" => 5
      },
      "level_3" => %{
        "level_3_1" => "test",
        "level_3_2" => 0
      }
    }
  end

  defp get_nested_params do
    [
      [
        %{
          "level_1" => %{
            "level_1_1" => "test",
            "level_1_2" => 0
          },
          "level_2" => [
            [
              %{
                "level_2_1" => "test",
                "level_2_2" => 0,
                "level_2_3" => "2017-01-01",
                "level_2_4" => 5
              }
            ]
          ],
          "level_3" => %{
            "level_3_1" => "test",
            "level_3_2" => 0
          }
        }
      ]
    ]
  end
end
