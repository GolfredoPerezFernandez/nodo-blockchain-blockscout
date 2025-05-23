defmodule Explorer.Chain.Address.CoinBalanceDaily do
  @moduledoc """
  Maximum `t:Explorer.Chain.Wei.t/0` `value` of `t:Explorer.Chain.Address.t/0` at the day.
  This table is used to display coin balance history chart.
  """

  use Explorer.Schema

  alias Explorer.Chain.{Address, Hash, Wei}

  @optional_fields ~w(value)a
  @required_fields ~w(address_hash day)a
  @allowed_fields @optional_fields ++ @required_fields

  @typedoc """
   * `address` - the `t:Explorer.Chain.Address.t/0`.
   * `address_hash` - foreign key for `address`.
   * `day` - the `t:Date.t/0`.
   * `inserted_at` - When the balance was first inserted into the database.
   * `updated_at` - When the balance was last updated.
   * `value` - the max balance (`value`) of `address` during the `day`.
  """
  @primary_key false
  typed_schema "address_coin_balances_daily" do
    field(:day, :date, null: false)
    field(:value, Wei)

    timestamps()

    belongs_to(:address, Address, foreign_key: :address_hash, references: :hash, type: Hash.Address, null: false)
  end

  @doc """
  Builds an `Ecto.Query` to fetch a series of balances by day for the given account. Each element in the series
  corresponds to the maximum balance in that day. Only the last `n` days of data are used.
  `n` is configurable via COIN_BALANCE_HISTORY_DAYS ENV var.
  """
  def balances_by_day(address_hash) do
    days_to_consider =
      Application.get_env(:block_scout_web, BlockScoutWeb.Chain.Address.CoinBalance)[:coin_balance_history_days]

    __MODULE__
    |> where([cbd], cbd.address_hash == ^address_hash)
    |> limit_time_interval(days_to_consider)
    |> select([cbd], %{date: cbd.day, value: cbd.value})
  end

  def limit_time_interval(query, days_to_consider) do
    query
    |> where(
      [cbd],
      cbd.day >= fragment("date_trunc('day', now() - CAST(? AS INTERVAL))", ^%Postgrex.Interval{days: days_to_consider})
    )
  end

  def changeset(_, params) when is_nil(params), do: :ignore

  def changeset(%__MODULE__{} = balance, params) when not is_nil(params) do
    balance
    |> cast(params, @allowed_fields)
    |> validate_required(@required_fields)
    |> unique_constraint(:day, name: :address_coin_balances_daily_address_hash_day_index)
  end

  @doc """
  Query to get latest balance by day for the given address
  """
  @spec latest_by_day_query(Hash.Address.t()) :: Ecto.Query.t()
  def latest_by_day_query(address_hash) do
    from(
      cbd in __MODULE__,
      where: cbd.address_hash == ^address_hash,
      order_by: [desc: :day],
      limit: 1
    )
  end
end
