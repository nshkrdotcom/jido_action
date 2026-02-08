defmodule JidoTest.Tools.Weather.ForecastCoverageTest do
  @moduledoc """
  Coverage tests for Jido.Tools.Weather.Forecast non-200 response path.
  """
  use JidoTest.ActionCase, async: false

  import Mimic

  alias Jido.Tools.Weather.Forecast

  @moduletag :capture_log

  setup :set_mimic_global

  describe "Forecast.run/2 non-200 status" do
    test "returns error for 500 status" do
      stub(Req, :request!, fn _opts ->
        %{
          status: 500,
          body: %{"detail" => "Internal error"},
          headers: %{"content-type" => "application/geo+json"}
        }
      end)

      assert {:error, %Jido.Action.Error.ExecutionFailureError{}} =
               Forecast.run(
                 %{
                   forecast_url: "https://api.weather.gov/gridpoints/LOT/75,72/forecast",
                   periods: 3,
                   format: :summary
                 },
                 %{}
               )
    end
  end
end
