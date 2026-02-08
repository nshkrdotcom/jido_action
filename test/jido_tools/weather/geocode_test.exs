defmodule JidoTest.Tools.Weather.GeocodeTest do
  use JidoTest.ActionCase, async: false

  import Mimic

  alias Jido.Tools.Weather.Geocode

  @moduletag :capture_log

  setup :set_mimic_global

  describe "run/2 successful geocoding" do
    test "geocodes a location string to coordinates" do
      stub(Req, :request!, fn _opts ->
        %{
          status: 200,
          body: [
            %{
              "lat" => "41.8781",
              "lon" => "-87.6298",
              "display_name" => "Chicago, Cook County, Illinois, USA"
            }
          ],
          headers: %{"content-type" => "application/json"}
        }
      end)

      assert {:ok, result} = Geocode.run(%{location: "Chicago, IL"}, %{})
      assert result.latitude == 41.8781
      assert result.longitude == -87.6298
      assert result.coordinates == "41.8781,-87.6298"
      assert result.display_name == "Chicago, Cook County, Illinois, USA"
    end

    test "handles float coordinate values" do
      stub(Req, :request!, fn _opts ->
        %{
          status: 200,
          body: [
            %{
              "lat" => 40.7128,
              "lon" => -74.006,
              "display_name" => "New York, NY"
            }
          ],
          headers: %{"content-type" => "application/json"}
        }
      end)

      assert {:ok, result} = Geocode.run(%{location: "New York"}, %{})
      assert result.latitude == 40.7128
      assert result.longitude == -74.006
    end

    test "handles integer coordinate values" do
      stub(Req, :request!, fn _opts ->
        %{
          status: 200,
          body: [
            %{
              "lat" => 42,
              "lon" => -88,
              "display_name" => "Somewhere"
            }
          ],
          headers: %{"content-type" => "application/json"}
        }
      end)

      assert {:ok, result} = Geocode.run(%{location: "Somewhere"}, %{})
      assert result.latitude == 42.0
      assert result.longitude == -88.0
    end
  end

  describe "run/2 error handling" do
    test "returns error for empty results" do
      stub(Req, :request!, fn _opts ->
        %{
          status: 200,
          body: [],
          headers: %{"content-type" => "application/json"}
        }
      end)

      assert {:error, %Jido.Action.Error.ExecutionFailureError{message: message}} =
               Geocode.run(%{location: "nonexistent-place-xyz"}, %{})

      assert message =~ "No results found"
    end

    test "returns error for non-200 API response" do
      stub(Req, :request!, fn _opts ->
        %{
          status: 500,
          body: %{"error" => "Internal server error"},
          headers: %{"content-type" => "application/json"}
        }
      end)

      assert {:error, %Jido.Action.Error.ExecutionFailureError{message: message}} =
               Geocode.run(%{location: "Chicago"}, %{})

      assert message =~ "Geocoding API error"
      assert message =~ "500"
    end

    test "returns error when HTTP request fails" do
      stub(Req, :request!, fn _opts ->
        raise RuntimeError, "Connection refused"
      end)

      assert {:error, %Jido.Action.Error.ExecutionFailureError{message: message}} =
               Geocode.run(%{location: "Chicago"}, %{})

      assert message =~ "Geocoding HTTP error"
    end
  end
end
