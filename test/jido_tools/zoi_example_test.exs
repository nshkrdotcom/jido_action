defmodule JidoTest.Tools.ZoiExampleTest do
  use ExUnit.Case, async: true

  alias Jido.Tools.ZoiExample

  @moduletag :capture_log

  describe "run/2 successful validation" do
    test "validates and transforms user registration data with age" do
      params = %{
        user: %{
          email: "  JOHN@EXAMPLE.COM  ",
          password: "SecurePass1!",
          name: "  John Doe  ",
          age: 30
        },
        priority: :high,
        metadata: %{source: :web}
      }

      assert {:ok, result} = Jido.Exec.run(ZoiExample, params)

      assert result.user.email == "john@example.com"
      assert result.user.name == "John Doe"
      assert result.user.age == 30
      assert result.priority == :high
      assert result.status == :approved
      assert is_integer(result.timestamp)
    end

    test "applies default priority when not provided" do
      params = %{
        user: %{
          email: "jane@example.com",
          password: "ValidPass1!",
          name: "Jane",
          age: 25
        }
      }

      assert {:ok, result} = Jido.Exec.run(ZoiExample, params)

      assert result.priority == :normal
      assert result.status == :pending
    end

    test "handles age field" do
      params = %{
        user: %{
          email: "age@example.com",
          password: "ValidPass1!",
          name: "Test User",
          age: 25
        }
      }

      assert {:ok, result} = Jido.Exec.run(ZoiExample, params)
      assert result.user.age == 25
    end

    test "low priority produces pending status" do
      params = %{
        user: %{
          email: "low@example.com",
          password: "ValidPass1!",
          name: "Low Priority",
          age: 20
        },
        priority: :low
      }

      assert {:ok, result} = Jido.Exec.run(ZoiExample, params)
      assert result.status == :pending
    end

    test "output validation fails when age is nil (absent)" do
      # When age is not provided, Map.get returns nil, which fails output_schema
      # because Zoi.optional means the key can be absent, not nil
      params = %{
        user: %{
          email: "noage@example.com",
          password: "ValidPass1!",
          name: "No Age"
        }
      }

      assert {:error, _} = Jido.Exec.run(ZoiExample, params)
    end
  end

  describe "run/2 validation failures" do
    test "rejects invalid email format" do
      params = %{
        user: %{
          email: "not-an-email",
          password: "SecurePass1!",
          name: "Test"
        }
      }

      assert {:error, _} = Jido.Exec.run(ZoiExample, params)
    end

    test "rejects short password" do
      params = %{
        user: %{
          email: "test@example.com",
          password: "Short1!",
          name: "Test"
        }
      }

      assert {:error, _} = Jido.Exec.run(ZoiExample, params)
    end

    test "rejects password without uppercase" do
      params = %{
        user: %{
          email: "test@example.com",
          password: "nouppercase1!",
          name: "Test"
        }
      }

      assert {:error, _} = Jido.Exec.run(ZoiExample, params)
    end

    test "rejects password without lowercase" do
      params = %{
        user: %{
          email: "test@example.com",
          password: "NOLOWERCASE1!",
          name: "Test"
        }
      }

      assert {:error, _} = Jido.Exec.run(ZoiExample, params)
    end

    test "rejects password without digit" do
      params = %{
        user: %{
          email: "test@example.com",
          password: "NoDigitHere!",
          name: "Test"
        }
      }

      assert {:error, _} = Jido.Exec.run(ZoiExample, params)
    end
  end
end
