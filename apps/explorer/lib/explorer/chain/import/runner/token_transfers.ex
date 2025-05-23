defmodule Explorer.Chain.Import.Runner.TokenTransfers do
  @moduledoc """
  Bulk imports `t:Explorer.Chain.TokenTransfer.t/0`.
  """

  require Ecto.Query

  import Ecto.Query, only: [from: 2]

  alias Ecto.{Changeset, Multi, Repo}
  alias Explorer.Chain.{Import, TokenTransfer}
  alias Explorer.Prometheus.Instrumenter

  @behaviour Import.Runner

  # milliseconds
  @timeout 60_000

  @type imported :: [TokenTransfer.t()]

  @impl Import.Runner
  def ecto_schema_module, do: TokenTransfer

  @impl Import.Runner
  def option_key, do: :token_transfers

  @impl Import.Runner
  def imported_table_row do
    %{
      value_type: "[#{ecto_schema_module()}.t()]",
      value_description: "List of `t:#{ecto_schema_module()}.t/0`s"
    }
  end

  @impl Import.Runner
  def run(multi, changes_list, %{timestamps: timestamps} = options) do
    insert_options =
      options
      |> Map.get(option_key(), %{})
      |> Map.take(~w(on_conflict timeout)a)
      |> Map.put_new(:timeout, @timeout)
      |> Map.put(:timestamps, timestamps)

    Multi.run(multi, :token_transfers, fn repo, _ ->
      Instrumenter.block_import_stage_runner(
        fn -> insert(repo, changes_list, insert_options) end,
        :block_referencing,
        :token_transfers,
        :token_transfers
      )
    end)
  end

  @impl Import.Runner
  def timeout, do: @timeout

  @spec insert(Repo.t(), [map()], %{required(:timeout) => timeout(), required(:timestamps) => Import.timestamps()}) ::
          {:ok, [TokenTransfer.t()]}
          | {:error, [Changeset.t()]}
  def insert(repo, changes_list, %{timeout: timeout, timestamps: timestamps} = options) when is_list(changes_list) do
    on_conflict = Map.get_lazy(options, :on_conflict, &default_on_conflict/0)

    # Enforce TokenTransfer ShareLocks order (see docs: sharelocks.md)
    ordered_changes_list =
      case Application.get_env(:explorer, :chain_type) do
        :celo -> Enum.sort_by(changes_list, &{&1.block_hash, &1.log_index})
        _ -> Enum.sort_by(changes_list, &{&1.transaction_hash, &1.block_hash, &1.log_index})
      end

    conflict_target =
      case Application.get_env(:explorer, :chain_type) do
        :celo -> [:log_index, :block_hash]
        _ -> [:transaction_hash, :log_index, :block_hash]
      end

    {:ok, inserted} =
      Import.insert_changes_list(
        repo,
        ordered_changes_list,
        conflict_target: conflict_target,
        on_conflict: on_conflict,
        for: TokenTransfer,
        returning: true,
        timeout: timeout,
        timestamps: timestamps
      )

    {:ok, inserted}
  end

  defp default_on_conflict do
    case Application.get_env(:explorer, :chain_type) do
      :celo ->
        from(
          token_transfer in TokenTransfer,
          update: [
            set: [
              # Don't update `log_index` as it is part of the composite primary
              # key and used for the conflict target
              transaction_hash: fragment("EXCLUDED.transaction_hash"),
              amount: fragment("EXCLUDED.amount"),
              from_address_hash: fragment("EXCLUDED.from_address_hash"),
              to_address_hash: fragment("EXCLUDED.to_address_hash"),
              token_contract_address_hash: fragment("EXCLUDED.token_contract_address_hash"),
              token_ids: fragment("EXCLUDED.token_ids"),
              token_type: fragment("EXCLUDED.token_type"),
              block_consensus: fragment("EXCLUDED.block_consensus"),
              inserted_at: fragment("LEAST(?, EXCLUDED.inserted_at)", token_transfer.inserted_at),
              updated_at: fragment("GREATEST(?, EXCLUDED.updated_at)", token_transfer.updated_at)
            ]
          ],
          where:
            fragment(
              "(EXCLUDED.amount, EXCLUDED.from_address_hash, EXCLUDED.to_address_hash, EXCLUDED.token_contract_address_hash, EXCLUDED.token_ids, EXCLUDED.token_type, EXCLUDED.block_consensus, EXCLUDED.transaction_hash) IS DISTINCT FROM (?, ?, ?, ?, ?, ?, ?, ?)",
              token_transfer.amount,
              token_transfer.from_address_hash,
              token_transfer.to_address_hash,
              token_transfer.token_contract_address_hash,
              token_transfer.token_ids,
              token_transfer.token_type,
              token_transfer.block_consensus,
              token_transfer.transaction_hash
            )
        )

      _ ->
        from(
          token_transfer in TokenTransfer,
          update: [
            set: [
              # Don't update `transaction_hash` as it is part of the composite primary key and used for the conflict target
              # Don't update `log_index` as it is part of the composite primary key and used for the conflict target
              amount: fragment("EXCLUDED.amount"),
              from_address_hash: fragment("EXCLUDED.from_address_hash"),
              to_address_hash: fragment("EXCLUDED.to_address_hash"),
              token_contract_address_hash: fragment("EXCLUDED.token_contract_address_hash"),
              token_ids: fragment("EXCLUDED.token_ids"),
              token_type: fragment("EXCLUDED.token_type"),
              block_consensus: fragment("EXCLUDED.block_consensus"),
              inserted_at: fragment("LEAST(?, EXCLUDED.inserted_at)", token_transfer.inserted_at),
              updated_at: fragment("GREATEST(?, EXCLUDED.updated_at)", token_transfer.updated_at)
            ]
          ],
          where:
            fragment(
              "(EXCLUDED.amount, EXCLUDED.from_address_hash, EXCLUDED.to_address_hash, EXCLUDED.token_contract_address_hash, EXCLUDED.token_ids, EXCLUDED.token_type, EXCLUDED.block_consensus) IS DISTINCT FROM (?, ?, ?, ?, ?, ?, ?)",
              token_transfer.amount,
              token_transfer.from_address_hash,
              token_transfer.to_address_hash,
              token_transfer.token_contract_address_hash,
              token_transfer.token_ids,
              token_transfer.token_type,
              token_transfer.block_consensus
            )
        )
    end
  end
end
