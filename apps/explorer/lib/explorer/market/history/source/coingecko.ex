defmodule Explorer.Market.History.Source.CoinGecko do
  @moduledoc """
  Adapter for fetching market history from https://coingecko.com.

  The history is fetched for the configured coin. You can specify a
  different coin by changing the targeted coin.

      # In config.exs
      config :explorer, coin: "POA"

  """
  require Logger
  alias Explorer.Market.History.Source
  alias Explorer.Market.History.{Source}
  alias HTTPoison.Response

  @behaviour Source

  @typep unix_timestamp :: non_neg_integer()

  @callback headers :: [any]
  def get_headers do
    if api_key() do
      [{"Content-Type", "application/json"},{"X-Cg-Pro-Api-Key", "#{api_key()}"}]
    else
      [{"Content-Type", "application/json"}]
    end
  end

  @impl Source
  def fetch_history(previous_days) do
    url = history_url(previous_days)
    headers = get_headers()
    case HTTPoison.get(url, headers) do
      {:ok, %Response{body: body, status_code: 200}} ->
        result =
          body
          |> format_data()
          |> reject_zeros()

        {:ok, result}

      _ ->
        :error
    end
  end

  defp api_key do
    Application.get_env(:explorer, Source)[:coingecko_api_key] || nil
  end

  @spec base_url :: String.t()
  defp base_url do
    if api_key() do
      base_pro_url()
    else
      base_free_url()
    end
  end

  defp base_free_url do
    Application.get_env(:explorer, Source)[:base_url] || "https://api.coingecko.com/api/v3"
  end

  defp base_pro_url do
    Application.get_env(:explorer, Source)[:base_pro_url] || "https://pro-api.coingecko.com/api/v3"
  end

  # @spec coin_id :: String.t()
  defp coin_id do
    explicit_coin_id = Application.get_env(:explorer, Source)[:coingecko_coin_id]
    {:ok, id} =
      if explicit_coin_id do
        {:ok, explicit_coin_id}
      else
        symbol = String.downcase(Explorer.coin())
        case coin_id(symbol) do
          {:ok, id} ->
            {:ok, id}

          _ ->
            {:ok, nil}
        end
      end
    if id, do: id, else: nil
  end

  def coin_id(symbol) do
    id_mapping = token_symbol_to_id_mapping_to_get_price(symbol)

    if id_mapping do
      {:ok, id_mapping}
    else
      url = "#{base_url()}/coins/list"

      symbol_downcase = String.downcase(symbol)
      headers = get_headers()
      case HTTPoison.get(url, headers) do
        {:ok, %Response{body: body, status_code: 200}} ->
          result =
            body
            |> find_id_symbol(symbol_downcase)

          {:ok, result}

        _ ->
          :error
      end
    end
  end

  @spec date(unix_timestamp()) :: Date.t()
  defp date(unix_timestamp) do
    unix_timestamp
    |> DateTime.from_unix!()
    |> DateTime.to_date()
  end

  @spec format_data(String.t()) :: [Source.record()]
  defp format_data(data) do
    json = Jason.decode!(data)
    Enum.map(json["prices"], fn x -> %{ closing_price: Decimal.new(to_string(Enum.at(x, 1))), date: date(div(Enum.at(x, 0), 1000)), opening_price: Decimal.new(to_string(Enum.at(x, 1))) } end)
  end

  @spec history_url(non_neg_integer()) :: String.t()
  defp history_url(previous_days) do
    query_params = %{
      "interval" => "1d",
      "days" => previous_days,
      "vs_currency" => "USD"
    }
    "#{base_url()}/coins/#{coin_id()}/market_chart?#{URI.encode_query(query_params)}"
  end

  defp reject_zeros(items) do
    Enum.reject(items, fn item ->
      Decimal.equal?(item.closing_price, 0) && Decimal.equal?(item.opening_price, 0)
    end)
  end

  defp token_symbol_to_id_mapping_to_get_price(symbol) do
    case symbol do
      "UNI" -> "uniswap"
      "SURF" -> "surf-finance"
      _symbol -> nil
    end
  end
  defp find_id_symbol(data, symbol_downcase) do
    json = Jason.decode!(data)
    symbol_data =
      Enum.find(json, fn item ->
        item["symbol"] == symbol_downcase
      end)

    if symbol_data, do: symbol_data["id"], else: nil
  end
end
