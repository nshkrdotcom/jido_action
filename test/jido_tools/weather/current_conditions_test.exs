defmodule JidoTest.Tools.Weather.CurrentConditionsTest do
  use JidoTest.ActionCase, async: false

  import Mimic

  alias Jido.Tools.Weather.CurrentConditions

  @moduletag :capture_log

  setup :set_mimic_global

  defp mock_stations_response(stations) do
    features =
      Enum.map(stations, fn station ->
        %{
          "properties" => %{
            "stationIdentifier" => station.id,
            "name" => station.name
          },
          "id" => station.url
        }
      end)

    %{
      status: 200,
      body: %{"features" => features},
      headers: %{"content-type" => "application/geo+json"}
    }
  end

  defp mock_conditions_response do
    %{
      status: 200,
      body: %{
        "properties" => %{
          "station" => "KORD",
          "timestamp" => "2025-08-24T19:00:00+00:00",
          "temperature" => %{"value" => 22.5, "unitCode" => "wmoUnit:degC"},
          "dewpoint" => %{"value" => 15.0, "unitCode" => "wmoUnit:degC"},
          "windDirection" => %{"value" => 270, "unitCode" => "wmoUnit:degree_(angle)"},
          "windSpeed" => %{"value" => 5.6, "unitCode" => "wmoUnit:km_h-1"},
          "windGust" => %{"value" => nil},
          "barometricPressure" => %{"value" => 101_325, "unitCode" => "wmoUnit:Pa"},
          "seaLevelPressure" => %{"value" => 101_500, "unitCode" => "wmoUnit:Pa"},
          "visibility" => %{"value" => 16_093, "unitCode" => "wmoUnit:m"},
          "maxTemperatureLast24Hours" => nil,
          "minTemperatureLast24Hours" => nil,
          "precipitationLastHour" => %{"value" => 0, "unitCode" => "wmoUnit:mm"},
          "precipitationLast3Hours" => nil,
          "precipitationLast6Hours" => nil,
          "relativeHumidity" => %{"value" => 65.2, "unitCode" => "wmoUnit:percent"},
          "windChill" => nil,
          "heatIndex" => %{"value" => 23.1, "unitCode" => "wmoUnit:degC"},
          "cloudLayers" => [%{"base" => %{"value" => 3048}, "amount" => "SCT"}],
          "textDescription" => "Partly Cloudy"
        }
      },
      headers: %{"content-type" => "application/geo+json"}
    }
  end

  defp setup_successful_mocks do
    stations_url = "https://api.weather.gov/gridpoints/LOT/76,73/stations"
    station_url = "https://api.weather.gov/stations/KORD"

    stub(Req, :request!, fn opts ->
      cond do
        opts[:url] == stations_url ->
          mock_stations_response([
            %{id: "KORD", name: "Chicago O'Hare", url: station_url},
            %{id: "KMDW", name: "Chicago Midway", url: "https://api.weather.gov/stations/KMDW"}
          ])

        String.contains?(opts[:url], "/observations/latest") ->
          mock_conditions_response()

        true ->
          raise "Unexpected URL: #{opts[:url]}"
      end
    end)

    stations_url
  end

  describe "run/2 successful conditions retrieval" do
    test "returns current conditions from nearest station" do
      stations_url = setup_successful_mocks()

      assert {:ok, conditions} =
               CurrentConditions.run(%{observation_stations_url: stations_url}, %{})

      assert conditions.station == "KORD"
      assert conditions.timestamp == "2025-08-24T19:00:00+00:00"
      assert conditions.temperature == %{value: 22.5, unit: "degC"}
      assert conditions.dewpoint == %{value: 15.0, unit: "degC"}
      assert conditions.wind_direction == %{value: 270, unit: "degree_(angle)"}
      assert conditions.wind_speed == %{value: 5.6, unit: "km_h-1"}
      assert conditions.wind_gust == nil
      assert conditions.barometric_pressure == %{value: 101_325, unit: "Pa"}
      assert conditions.sea_level_pressure == %{value: 101_500, unit: "Pa"}
      assert conditions.visibility == %{value: 16_093, unit: "m"}
      assert conditions.max_temperature_last_24_hours == nil
      assert conditions.min_temperature_last_24_hours == nil
      assert conditions.precipitation_last_hour == %{value: 0, unit: "mm"}
      assert conditions.precipitation_last_3_hours == nil
      assert conditions.precipitation_last_6_hours == nil
      assert conditions.relative_humidity == %{value: 65.2, unit: "percent"}
      assert conditions.wind_chill == nil
      assert conditions.heat_index == %{value: 23.1, unit: "degC"}
      assert conditions.cloud_layers == [%{"base" => %{"value" => 3048}, "amount" => "SCT"}]
      assert conditions.text_description == "Partly Cloudy"
    end
  end

  describe "run/2 error handling" do
    test "returns error when no observation stations available" do
      stations_url = "https://api.weather.gov/gridpoints/LOT/76,73/stations"

      stub(Req, :request!, fn _opts ->
        %{
          status: 200,
          body: %{"features" => []},
          headers: %{"content-type" => "application/geo+json"}
        }
      end)

      assert {:error, %Jido.Action.Error.ExecutionFailureError{message: message}} =
               CurrentConditions.run(%{observation_stations_url: stations_url}, %{})

      assert message =~ "No observation stations available"
    end

    test "returns error when stations API returns non-200" do
      stations_url = "https://api.weather.gov/gridpoints/LOT/76,73/stations"

      stub(Req, :request!, fn _opts ->
        %{
          status: 500,
          body: %{"detail" => "Internal server error"},
          headers: %{"content-type" => "application/problem+json"}
        }
      end)

      assert {:error, %Jido.Action.Error.ExecutionFailureError{}} =
               CurrentConditions.run(%{observation_stations_url: stations_url}, %{})
    end

    test "returns error when conditions API returns non-200" do
      stations_url = "https://api.weather.gov/gridpoints/LOT/76,73/stations"
      station_url = "https://api.weather.gov/stations/KORD"

      stub(Req, :request!, fn opts ->
        cond do
          opts[:url] == stations_url ->
            mock_stations_response([%{id: "KORD", name: "Chicago O'Hare", url: station_url}])

          String.contains?(opts[:url], "/observations/latest") ->
            %{
              status: 503,
              body: %{"detail" => "Service unavailable"},
              headers: %{"content-type" => "application/problem+json"}
            }

          true ->
            raise "Unexpected URL: #{opts[:url]}"
        end
      end)

      assert {:error, %Jido.Action.Error.ExecutionFailureError{message: message}} =
               CurrentConditions.run(%{observation_stations_url: stations_url}, %{})

      assert message =~ "Failed to get current conditions"
    end

    test "returns error when HTTP request fails" do
      stations_url = "https://api.weather.gov/gridpoints/LOT/76,73/stations"

      stub(Req, :request!, fn _opts ->
        raise RuntimeError, "Connection refused"
      end)

      assert {:error, %Jido.Action.Error.ExecutionFailureError{message: message}} =
               CurrentConditions.run(%{observation_stations_url: stations_url}, %{})

      assert message =~ "HTTP error getting stations"
    end
  end

  describe "format_measurement/1 edge cases" do
    test "handles measurements with different unit code formats" do
      stations_url = "https://api.weather.gov/gridpoints/LOT/76,73/stations"
      station_url = "https://api.weather.gov/stations/KORD"

      stub(Req, :request!, fn opts ->
        cond do
          opts[:url] == stations_url ->
            mock_stations_response([%{id: "KORD", name: "Chicago O'Hare", url: station_url}])

          String.contains?(opts[:url], "/observations/latest") ->
            %{
              status: 200,
              body: %{
                "properties" => %{
                  "station" => "KORD",
                  "timestamp" => "2025-08-24T19:00:00+00:00",
                  "temperature" => %{"value" => 22.5, "unitCode" => "rawUnit"},
                  "dewpoint" => %{"value" => nil},
                  "windDirection" => nil,
                  "windSpeed" => nil,
                  "windGust" => nil,
                  "barometricPressure" => nil,
                  "seaLevelPressure" => nil,
                  "visibility" => nil,
                  "maxTemperatureLast24Hours" => nil,
                  "minTemperatureLast24Hours" => nil,
                  "precipitationLastHour" => nil,
                  "precipitationLast3Hours" => nil,
                  "precipitationLast6Hours" => nil,
                  "relativeHumidity" => nil,
                  "windChill" => nil,
                  "heatIndex" => nil,
                  "cloudLayers" => [],
                  "textDescription" => "Clear"
                }
              },
              headers: %{"content-type" => "application/geo+json"}
            }

          true ->
            raise "Unexpected URL: #{opts[:url]}"
        end
      end)

      assert {:ok, conditions} =
               CurrentConditions.run(%{observation_stations_url: stations_url}, %{})

      # Non-wmoUnit prefix gets passed through as-is
      assert conditions.temperature == %{value: 22.5, unit: "rawUnit"}
      # nil value measurement returns nil
      assert conditions.dewpoint == nil
      # nil measurement returns nil
      assert conditions.wind_direction == nil
    end
  end
end
