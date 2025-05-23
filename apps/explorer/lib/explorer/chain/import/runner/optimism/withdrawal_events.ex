defmodule Explorer.Chain.Import.Runner.Optimism.WithdrawalEvents do
  @moduledoc """
  Bulk imports `t:Explorer.Chain.Optimism.WithdrawalEvent.t/0`.
  """

  require Ecto.Query

  alias Ecto.{Changeset, Multi, Repo}
  alias Explorer.Chain.Import
  alias Explorer.Chain.Optimism.WithdrawalEvent
  alias Explorer.Prometheus.Instrumenter

  import Ecto.Query, only: [from: 2]

  @behaviour Import.Runner

  # milliseconds
  @timeout 60_000

  @type imported :: [WithdrawalEvent.t()]

  @impl Import.Runner
  def ecto_schema_module, do: WithdrawalEvent

  @impl Import.Runner
  def option_key, do: :optimism_withdrawal_events

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

    Multi.run(multi, :insert_withdrawal_events, fn repo, _ ->
      Instrumenter.block_import_stage_runner(
        fn -> insert(repo, changes_list, insert_options) end,
        :block_referencing,
        :optimism_withdrawal_events,
        :optimism_withdrawal_events
      )
    end)
  end

  @impl Import.Runner
  def timeout, do: @timeout

  @spec insert(Repo.t(), [map()], %{required(:timeout) => timeout(), required(:timestamps) => Import.timestamps()}) ::
          {:ok, [WithdrawalEvent.t()]}
          | {:error, [Changeset.t()]}
  def insert(repo, changes_list, %{timeout: timeout, timestamps: timestamps} = options) when is_list(changes_list) do
    on_conflict = Map.get_lazy(options, :on_conflict, &default_on_conflict/0)

    # Enforce WithdrawalEvent ShareLocks order (see docs: sharelock.md)
    ordered_changes_list = Enum.sort_by(changes_list, &{&1.withdrawal_hash, &1.l1_event_type, &1.l1_transaction_hash})

    {:ok, inserted} =
      Import.insert_changes_list(
        repo,
        ordered_changes_list,
        for: WithdrawalEvent,
        returning: true,
        timeout: timeout,
        timestamps: timestamps,
        conflict_target: [:withdrawal_hash, :l1_event_type, :l1_transaction_hash],
        on_conflict: on_conflict
      )

    {:ok, inserted}
  end

  defp default_on_conflict do
    from(
      we in WithdrawalEvent,
      update: [
        set: [
          # don't update `withdrawal_hash` as it is a part of the composite primary key and used for the conflict target
          # don't update `l1_event_type` as it is a part of the composite primary key and used for the conflict target
          # don't update `l1_transaction_hash` as it is a part of the composite primary key and used for the conflict target
          l1_timestamp: fragment("EXCLUDED.l1_timestamp"),
          l1_block_number: fragment("EXCLUDED.l1_block_number"),
          game_index: fragment("EXCLUDED.game_index"),
          inserted_at: fragment("LEAST(?, EXCLUDED.inserted_at)", we.inserted_at),
          updated_at: fragment("GREATEST(?, EXCLUDED.updated_at)", we.updated_at)
        ]
      ],
      where:
        fragment(
          "(EXCLUDED.l1_timestamp, EXCLUDED.l1_block_number, EXCLUDED.game_index) IS DISTINCT FROM (?, ?, ?)",
          we.l1_timestamp,
          we.l1_block_number,
          we.game_index
        )
    )
  end
end
