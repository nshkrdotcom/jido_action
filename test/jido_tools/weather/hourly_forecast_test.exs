defmodule JidoTest.Tools.Weather.HourlyForecastTest do
  use JidoTest.ActionCase, async: false

  import Mimic

  alias Jido.Tools.Weather.HourlyForecast

  @moduletag :capture_log

  setup :set_mimic_global

  @hourly_url "https://api.weather.gov/gridpoints/LOT/76,73/forecast/hourly"

  defp mock_hourly_periods(count) do
    Enum.map(1..count, fn i ->
      %{
        "startTime" =>
          "2025-08-24T#{String.pad_leading(Integer.to_string(rem(i, 24)), 2, "0")}:00:00-05:00",
        "endTime" =>
          "2025-08-24T#{String.pad_leading(Integer.to_string(rem(i + 1, 24)), 2, "0")}:00:00-05:00",
        "temperature" => 60 + i,
        "temperatureUnit" => "F",
        "windSpeed" => "#{5 + i} mph",
        "windDirection" => "NW",
        "shortForecast" => "Partly Cloudy",
        "probabilityOfPrecipitation" => %{"value" => 10 + i},
        "relativeHumidity" => %{"value" => 50 + i},
        "dewpoint" => %{"value" => 12.0 + i * 0.5}
      }
    end)
  end

  describe "run/2 successful forecast retrieval" do
    test "returns hourly forecast with default hours (24)" do
      periods = mock_hourly_periods(30)

      stub(Req, :request!, fn _opts ->
        %{
          status: 200,
          body: %{
            "properties" => %{
              "updated" => "2025-08-24T18:00:00+00:00",
              "periods" => periods
            }
          },
          headers: %{"content-type" => "application/geo+json"}
        }
      end)

      assert {:ok, result} =
               HourlyForecast.run(%{hourly_forecast_url: @hourly_url}, %{})

      assert result.hourly_forecast_url == @hourly_url
      assert result.updated == "2025-08-24T18:00:00+00:00"
      assert result.total_periods == 30
      assert length(result.periods) == 24

      first_period = List.first(result.periods)
      assert Map.has_key?(first_period, :start_time)
      assert Map.has_key?(first_period, :end_time)
      assert Map.has_key?(first_period, :temperature)
      assert Map.has_key?(first_period, :temperature_unit)
      assert Map.has_key?(first_period, :wind_speed)
      assert Map.has_key?(first_period, :wind_direction)
      assert Map.has_key?(first_period, :short_forecast)
      assert Map.has_key?(first_period, :probability_of_precipitation)
      assert Map.has_key?(first_period, :relative_humidity)
      assert Map.has_key?(first_period, :dewpoint)
    end

    test "respects custom hours parameter" do
      periods = mock_hourly_periods(30)

      stub(Req, :request!, fn _opts ->
        %{
          status: 200,
          body: %{
            "properties" => %{
              "updated" => "2025-08-24T18:00:00+00:00",
              "periods" => periods
            }
          },
          headers: %{"content-type" => "application/geo+json"}
        }
      end)

      assert {:ok, result} =
               HourlyForecast.run(%{hourly_forecast_url: @hourly_url, hours: 6}, %{})

      assert length(result.periods) == 6
      assert result.total_periods == 30
    end

    test "returns all periods when fewer than requested hours" do
      periods = mock_hourly_periods(3)

      stub(Req, :request!, fn _opts ->
        %{
          status: 200,
          body: %{
            "properties" => %{
              "updated" => "2025-08-24T18:00:00+00:00",
              "periods" => periods
            }
          },
          headers: %{"content-type" => "application/geo+json"}
        }
      end)

      assert {:ok, result} =
               HourlyForecast.run(%{hourly_forecast_url: @hourly_url, hours: 24}, %{})

      assert length(result.periods) == 3
      assert result.total_periods == 3
    end
  end

  describe "run/2 error handling" do
    test "returns error when API returns non-200 status" do
      stub(Req, :request!, fn _opts ->
        %{
          status: 500,
          body: %{"detail" => "Internal server error"},
          headers: %{"content-type" => "application/problem+json"}
        }
      end)

      assert {:error, %Jido.Action.Error.ExecutionFailureError{message: message}} =
               HourlyForecast.run(%{hourly_forecast_url: @hourly_url}, %{})

      assert message =~ "NWS hourly forecast API error"
    end

    test "returns error when HTTP request fails" do
      stub(Req, :request!, fn _opts ->
        raise RuntimeError, "Connection timeout"
      end)

      assert {:error, %Jido.Action.Error.ExecutionFailureError{message: message}} =
               HourlyForecast.run(%{hourly_forecast_url: @hourly_url}, %{})

      assert message =~ "HTTP error"
    end
  end
end
