defmodule Explorer.Chain.Import.Runner.InternalTransactions do
  @moduledoc """
  Bulk imports `t:Explorer.Chain.InternalTransactions.t/0`.
  """

  require Ecto.Query
  require Logger

  alias Ecto.Adapters.SQL
  alias Ecto.{Changeset, Multi, Repo}
  alias EthereumJSONRPC.Utility.RangesHelper

  alias Explorer.Chain.{
    Block,
    Hash,
    Import,
    InternalTransaction,
    PendingOperationsHelper,
    PendingTransactionOperation,
    Transaction
  }

  alias Explorer.Chain.Events.Publisher
  alias Explorer.Chain.Import.Runner
  alias Explorer.Prometheus.Instrumenter
  alias Explorer.Repo, as: ExplorerRepo
  alias Explorer.Utility.MissingRangesManipulator

  import Ecto.Query

  @behaviour Runner

  # milliseconds
  @timeout 60_000

  @type imported :: [InternalTransaction.t()]

  @impl Runner
  def ecto_schema_module, do: InternalTransaction

  @impl Runner
  def option_key, do: :internal_transactions

  @impl Runner
  def imported_table_row do
    %{
      value_type: "[%{index: non_neg_integer(), transaction_hash: Explorer.Chain.Hash.t()}]",
      value_description: "List of maps of the `t:Explorer.Chain.InternalTransaction.t/0` `index` and `transaction_hash`"
    }
  end

  @impl Runner
  def run(multi, changes_list, %{timestamps: timestamps} = options) when is_map(options) do
    insert_options =
      options
      |> Map.get(option_key(), %{})
      |> Map.take(~w(on_conflict timeout)a)
      |> Map.put_new(:timeout, @timeout)
      |> Map.put(:timestamps, timestamps)

    transactions_timeout = options[Runner.Transactions.option_key()][:timeout] || Runner.Transactions.timeout()

    update_transactions_options = %{timeout: transactions_timeout, timestamps: timestamps}

    # filter out params with just `block_number` (indicating blocks without internal transactions)
    internal_transactions_params = Enum.filter(changes_list, &Map.has_key?(&1, :type))

    # Enforce ShareLocks tables order (see docs: sharelocks.md)
    multi
    |> Multi.run(:acquire_blocks, fn repo, _ ->
      Instrumenter.block_import_stage_runner(
        fn -> acquire_blocks(repo, changes_list) end,
        :block_pending,
        :internal_transactions,
        :acquire_blocks
      )
    end)
    |> Multi.run(:acquire_pending_internal_transactions, fn repo, %{acquire_blocks: block_hashes} ->
      Instrumenter.block_import_stage_runner(
        fn -> acquire_pending_internal_transactions(repo, block_hashes) end,
        :block_pending,
        :internal_transactions,
        :acquire_pending_internal_transactions
      )
    end)
    |> Multi.run(:acquire_transactions, fn repo, %{acquire_pending_internal_transactions: pending_ops_hashes} ->
      Instrumenter.block_import_stage_runner(
        fn -> acquire_transactions(repo, pending_ops_hashes) end,
        :block_pending,
        :internal_transactions,
        :acquire_transactions
      )
    end)
    |> Multi.run(:invalid_block_numbers, fn _, %{acquire_transactions: transactions} ->
      Instrumenter.block_import_stage_runner(
        fn -> invalid_block_numbers(transactions, internal_transactions_params) end,
        :block_pending,
        :internal_transactions,
        :invalid_block_numbers
      )
    end)
    |> Multi.run(:valid_internal_transactions, fn _,
                                                  %{
                                                    acquire_transactions: transactions,
                                                    invalid_block_numbers: invalid_block_numbers
                                                  } ->
      Instrumenter.block_import_stage_runner(
        fn ->
          valid_internal_transactions(
            transactions,
            internal_transactions_params,
            invalid_block_numbers
          )
        end,
        :block_pending,
        :internal_transactions,
        :valid_internal_transactions
      )
    end)
    |> Multi.run(:valid_internal_transactions_without_first_traces_of_trivial_transactions, fn _,
                                                                                               %{
                                                                                                 valid_internal_transactions:
                                                                                                   valid_internal_transactions
                                                                                               } ->
      Instrumenter.block_import_stage_runner(
        fn -> valid_internal_transactions_without_first_trace(valid_internal_transactions) end,
        :block_pending,
        :internal_transactions,
        :valid_internal_transactions_without_first_traces_of_trivial_transactions
      )
    end)
    |> Multi.run(:maybe_shrink_internal_transactions_params, fn _,
                                                                %{
                                                                  valid_internal_transactions_without_first_traces_of_trivial_transactions:
                                                                    valid_internal_transactions_without_first_traces_of_trivial_transactions
                                                                } ->
      Instrumenter.block_import_stage_runner(
        fn ->
          maybe_shrink_internal_transactions_params(
            valid_internal_transactions_without_first_traces_of_trivial_transactions
          )
        end,
        :block_pending,
        :internal_transactions,
        :maybe_shrink_internal_transactions_params
      )
    end)
    |> Multi.run(:internal_transactions, fn repo,
                                            %{
                                              maybe_shrink_internal_transactions_params:
                                                shrink_internal_transactions_params
                                            } ->
      Instrumenter.block_import_stage_runner(
        fn ->
          insert(repo, shrink_internal_transactions_params, insert_options)
        end,
        :block_pending,
        :internal_transactions,
        :internal_transactions
      )
    end)
    |> Multi.run(:update_transactions, fn repo,
                                          %{
                                            valid_internal_transactions: valid_internal_transactions,
                                            acquire_transactions: transactions
                                          } ->
      Instrumenter.block_import_stage_runner(
        fn -> update_transactions(repo, valid_internal_transactions, transactions, update_transactions_options) end,
        :block_pending,
        :internal_transactions,
        :update_transactions
      )
    end)
    |> Multi.run(:set_refetch_needed_for_invalid_blocks, fn repo, %{invalid_block_numbers: invalid_block_numbers} ->
      Instrumenter.block_import_stage_runner(
        fn -> set_refetch_needed_for_invalid_blocks(repo, invalid_block_numbers, timestamps) end,
        :block_pending,
        :internal_transactions,
        :set_refetch_needed_for_invalid_blocks
      )
    end)
    |> Multi.run(:update_pending_blocks_status, fn repo,
                                                   %{
                                                     acquire_pending_internal_transactions: pending_ops_hashes,
                                                     set_refetch_needed_for_invalid_blocks: invalid_block_hashes
                                                   } ->
      Instrumenter.block_import_stage_runner(
        fn -> update_pending_blocks_status(repo, pending_ops_hashes, invalid_block_hashes) end,
        :block_pending,
        :internal_transactions,
        :update_pending_blocks_status
      )
    end)
  end

  def run_insert_only(changes_list, %{timestamps: timestamps} = options) when is_map(options) do
    insert_options =
      options
      |> Map.get(option_key(), %{})
      |> Map.take(~w(on_conflict timeout)a)
      |> Map.put_new(:timeout, @timeout)
      |> Map.put(:timestamps, timestamps)

    # filter out params with just `block_number` (indicating blocks without internal transactions)
    internal_transactions_params = Enum.filter(changes_list, &Map.has_key?(&1, :type))

    # Enforce ShareLocks tables order (see docs: sharelocks.md)
    with {:ok, data} <-
           Multi.new()
           |> Multi.run(:internal_transactions, fn repo, _ ->
             insert(repo, internal_transactions_params, insert_options)
           end)
           |> ExplorerRepo.transaction() do
      Publisher.broadcast(data, :on_demand)
    end
  end

  @impl Runner
  def timeout, do: @timeout

  @spec insert(Repo.t(), [map], %{
          optional(:on_conflict) => Runner.on_conflict(),
          required(:timeout) => timeout,
          required(:timestamps) => Import.timestamps()
        }) ::
          {:ok, [%{index: non_neg_integer, transaction_hash: Hash.t()}]}
          | {:error, [Changeset.t()]}
  defp insert(repo, valid_internal_transactions, %{timeout: timeout, timestamps: timestamps} = options)
       when is_list(valid_internal_transactions) do
    on_conflict = Map.get_lazy(options, :on_conflict, &default_on_conflict/0)

    ordered_changes_list = Enum.sort_by(valid_internal_transactions, &{&1.transaction_hash, &1.index})

    {:ok, internal_transactions} =
      Import.insert_changes_list(
        repo,
        ordered_changes_list,
        conflict_target: [:block_hash, :block_index],
        for: InternalTransaction,
        on_conflict: on_conflict,
        returning: true,
        timeout: timeout,
        timestamps: timestamps
      )

    {:ok, internal_transactions}
  end

  defp default_on_conflict do
    from(
      internal_transaction in InternalTransaction,
      update: [
        set: [
          block_number: fragment("EXCLUDED.block_number"),
          call_type: fragment("EXCLUDED.call_type"),
          created_contract_address_hash: fragment("EXCLUDED.created_contract_address_hash"),
          created_contract_code: fragment("EXCLUDED.created_contract_code"),
          error: fragment("EXCLUDED.error"),
          from_address_hash: fragment("EXCLUDED.from_address_hash"),
          gas: fragment("EXCLUDED.gas"),
          gas_used: fragment("EXCLUDED.gas_used"),
          index: fragment("EXCLUDED.index"),
          init: fragment("EXCLUDED.init"),
          input: fragment("EXCLUDED.input"),
          output: fragment("EXCLUDED.output"),
          to_address_hash: fragment("EXCLUDED.to_address_hash"),
          trace_address: fragment("EXCLUDED.trace_address"),
          transaction_hash: fragment("EXCLUDED.transaction_hash"),
          transaction_index: fragment("EXCLUDED.transaction_index"),
          type: fragment("EXCLUDED.type"),
          value: fragment("EXCLUDED.value"),
          inserted_at: fragment("LEAST(?, EXCLUDED.inserted_at)", internal_transaction.inserted_at),
          updated_at: fragment("GREATEST(?, EXCLUDED.updated_at)", internal_transaction.updated_at)
          # Don't update `block_hash` as it is used for the conflict target
          # Don't update `block_index` as it is used for the conflict target
        ]
      ],
      # `IS DISTINCT FROM` is used because it allows `NULL` to be equal to itself
      where:
        fragment(
          "(EXCLUDED.transaction_hash, EXCLUDED.index, EXCLUDED.call_type, EXCLUDED.created_contract_address_hash, EXCLUDED.created_contract_code, EXCLUDED.error, EXCLUDED.from_address_hash, EXCLUDED.gas, EXCLUDED.gas_used, EXCLUDED.init, EXCLUDED.input, EXCLUDED.output, EXCLUDED.to_address_hash, EXCLUDED.trace_address, EXCLUDED.transaction_index, EXCLUDED.type, EXCLUDED.value) IS DISTINCT FROM (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
          internal_transaction.transaction_hash,
          internal_transaction.index,
          internal_transaction.call_type,
          internal_transaction.created_contract_address_hash,
          internal_transaction.created_contract_code,
          internal_transaction.error,
          internal_transaction.from_address_hash,
          internal_transaction.gas,
          internal_transaction.gas_used,
          internal_transaction.init,
          internal_transaction.input,
          internal_transaction.output,
          internal_transaction.to_address_hash,
          internal_transaction.trace_address,
          internal_transaction.transaction_index,
          internal_transaction.type,
          internal_transaction.value
        )
    )
  end

  defp acquire_blocks(repo, changes_list) do
    block_numbers =
      changes_list
      |> Enum.map(& &1.block_number)
      |> Enum.uniq()

    query =
      from(
        block in Block,
        where: block.number in ^block_numbers and block.consensus == true,
        select: block.hash,
        # Enforce Block ShareLocks order (see docs: sharelocks.md)
        order_by: [asc: block.hash],
        lock: "FOR NO KEY UPDATE"
      )

    {:ok, repo.all(query)}
  end

  defp acquire_pending_internal_transactions(repo, block_hashes) do
    case PendingOperationsHelper.pending_operations_type() do
      "blocks" ->
        query =
          block_hashes
          |> PendingOperationsHelper.block_hash_in_query()
          |> select([pbo], pbo.block_hash)
          |> order_by([pbo], asc: pbo.block_hash)
          |> lock("FOR UPDATE")

        {:ok, {:block_hashes, repo.all(query)}}

      "transactions" ->
        query =
          from(
            pending_ops in PendingTransactionOperation,
            join: transaction in assoc(pending_ops, :transaction),
            where: transaction.block_hash in ^block_hashes,
            select: pending_ops.transaction_hash,
            # Enforce PendingTransactionOperation ShareLocks order (see docs: sharelocks.md)
            order_by: [asc: pending_ops.transaction_hash],
            lock: "FOR UPDATE"
          )

        {:ok, {:transaction_hashes, repo.all(query)}}
    end
  end

  defp acquire_transactions(repo, pending_ops_hashes) do
    dynamic_condition =
      case pending_ops_hashes do
        {:block_hashes, block_hashes} -> dynamic([t], t.block_hash in ^block_hashes)
        {:transaction_hashes, transaction_hashes} -> dynamic([t], t.hash in ^transaction_hashes)
      end

    query =
      from(
        t in Transaction,
        where: ^dynamic_condition,
        select: map(t, [:hash, :block_hash, :block_number, :cumulative_gas_used, :status]),
        # Enforce Transaction ShareLocks order (see docs: sharelocks.md)
        order_by: [asc: t.hash],
        lock: "FOR NO KEY UPDATE"
      )

    {:ok, repo.all(query)}
  end

  defp invalid_block_numbers(transactions, internal_transactions_params) do
    # Finds all mismatches between transactions and internal transactions
    # for a block number:
    # - there are no internal transactions for some transactions
    # - there are internal transactions with a different block number than their transactions
    # Returns block numbers where any of these issues is found

    # Note: the case "# - there are no transactions for some internal transactions" was removed because it caused the issue https://github.com/blockscout/blockscout/issues/3367
    # when the last block with transactions loses consensus in endless loop. In order to return this case:
    # common_tuples = MapSet.intersection(required_tuples, candidate_tuples) #should be added
    # |> MapSet.difference(internal_transactions_tuples) should be replaced with |> MapSet.difference(common_tuples)

    # Note: for zetachain or if empty traces are explicitly allowed,
    # the case "# - there are no internal transactions for some transactions" is removed since
    # there are may be non-traceable transactions

    transactions_tuples = MapSet.new(transactions, &{&1.hash, &1.block_number})

    internal_transactions_tuples = MapSet.new(internal_transactions_params, &{&1.transaction_hash, &1.block_number})

    all_tuples = MapSet.union(transactions_tuples, internal_transactions_tuples)

    invalid_block_numbers =
      if allow_non_traceable_transactions?() do
        Enum.reduce(internal_transactions_tuples, [], fn {transaction_hash, block_number}, acc ->
          # credo:disable-for-next-line
          case Enum.find(transactions_tuples, fn {t_hash, _block_number} -> t_hash == transaction_hash end) do
            nil -> acc
            {_t_hash, ^block_number} -> acc
            _ -> [block_number | acc]
          end
        end)
      else
        all_tuples
        |> MapSet.difference(internal_transactions_tuples)
        |> MapSet.new(fn {_hash, block_number} -> block_number end)
        |> MapSet.to_list()
      end

    {:ok, invalid_block_numbers}
  end

  defp allow_non_traceable_transactions? do
    Application.get_env(:explorer, :chain_type) == :zetachain or
      (Application.get_env(:explorer, :json_rpc_named_arguments)[:variant] == EthereumJSONRPC.Geth and
         Application.get_env(:ethereum_jsonrpc, EthereumJSONRPC.Geth)[:allow_empty_traces?])
  end

  defp valid_internal_transactions(transactions, internal_transactions_params, invalid_block_numbers) do
    if Enum.empty?(transactions) do
      {:ok, []}
    else
      blocks_map = Map.new(transactions, &{&1.block_number, &1.block_hash})

      valid_internal_transactions =
        internal_transactions_params
        |> Enum.group_by(& &1.block_number)
        |> Map.drop(invalid_block_numbers)
        |> Enum.flat_map(fn item ->
          compose_entry_wrapper(item, blocks_map)
        end)

      {:ok, valid_internal_transactions}
    end
  end

  defp compose_entry_wrapper(item, blocks_map) do
    case item do
      {block_number, entries} ->
        compose_entry(entries, blocks_map, block_number)

      _ ->
        []
    end
  end

  defp compose_entry(entries, blocks_map, block_number) do
    if Map.has_key?(blocks_map, block_number) do
      block_hash = Map.fetch!(blocks_map, block_number)

      entries
      |> Enum.sort_by(
        &{(Map.has_key?(&1, :transaction_index) && &1.transaction_index) || &1.transaction_hash, &1.index}
      )
      |> Enum.with_index()
      |> Enum.map(fn {entry, index} ->
        entry
        |> Map.put(:block_hash, block_hash)
        |> Map.put(:block_index, index)
      end)
    else
      []
    end
  end

  defp valid_internal_transactions_without_first_trace(valid_internal_transactions) do
    json_rpc_named_arguments = Application.fetch_env!(:indexer, :json_rpc_named_arguments)
    variant = Keyword.fetch!(json_rpc_named_arguments, :variant)

    # we exclude first traces from storing in the DB only in case of Nethermind variant (Nethermind/OpenEthereum). Todo: implement the same for Geth
    if variant == EthereumJSONRPC.Nethermind do
      valid_internal_transactions_without_first_trace =
        valid_internal_transactions
        |> Enum.reject(fn trace ->
          trace[:index] == 0
        end)

      {:ok, valid_internal_transactions_without_first_trace}
    else
      {:ok, valid_internal_transactions}
    end
  end

  defp maybe_shrink_internal_transactions_params(internal_transactions) do
    if Application.get_env(:explorer, :shrink_internal_transactions_enabled) do
      shrunk_internal_transactions =
        Enum.map(internal_transactions, fn it ->
          it
          |> Map.delete(:output)
          |> Map.replace(:input, it[:input] && Map.put(it[:input], :bytes, binary_slice(it[:input].bytes, 0, 4)))
        end)

      {:ok, shrunk_internal_transactions}
    else
      {:ok, internal_transactions}
    end
  end

  def defer_internal_transactions_primary_key(repo) do
    # Allows internal_transactions primary key to not be checked during the
    # DB transactions and instead be checked only at the end of it.
    # This allows us to use a more efficient upserting logic, while keeping the
    # uniqueness valid.
    SQL.query(repo, "SET CONSTRAINTS internal_transactions_pkey DEFERRED")
  end

  defp update_transactions(repo, valid_internal_transactions, transactions, %{
         timeout: timeout,
         timestamps: timestamps
       }) do
    valid_internal_transactions_count = Enum.count(valid_internal_transactions)

    if valid_internal_transactions_count == 0 do
      {:ok, nil}
    else
      params =
        valid_internal_transactions
        |> Enum.filter(fn internal_transaction ->
          internal_transaction[:index] == 0
        end)
        |> Enum.map(fn trace ->
          %{
            block_hash: Map.get(trace, :block_hash),
            block_number: Map.get(trace, :block_number),
            gas_used: Map.get(trace, :gas_used),
            transaction_hash: Map.get(trace, :transaction_hash),
            created_contract_address_hash: Map.get(trace, :created_contract_address_hash),
            error: Map.get(trace, :error),
            status: if(is_nil(Map.get(trace, :error)), do: :ok, else: :error)
          }
        end)
        |> Enum.filter(fn transaction_hash -> transaction_hash != nil end)

      transaction_hashes =
        valid_internal_transactions
        |> MapSet.new(& &1.transaction_hash)
        |> MapSet.to_list()

      json_rpc_named_arguments = Application.fetch_env!(:indexer, :json_rpc_named_arguments)

      result =
        Enum.reduce_while(params, 0, fn first_trace, transaction_hashes_iterator ->
          transaction_hash = Map.get(first_trace, :transaction_hash)

          transaction_from_db = find_transaction(transactions, transaction_hash)

          update_transactions_inner_wrapper(
            transaction_from_db,
            repo,
            valid_internal_transactions,
            transaction_hash,
            json_rpc_named_arguments,
            transaction_hashes,
            transaction_hashes_iterator,
            timeout,
            timestamps,
            first_trace
          )
        end)

      case result do
        %{exception: _} ->
          {:error, result}

        _ ->
          {:ok, result}
      end
    end
  end

  defp find_transaction(transactions, transaction_hash) do
    transactions
    |> Enum.find(fn transaction ->
      transaction.hash == transaction_hash
    end)
  end

  # credo:disable-for-next-line
  defp update_transactions_inner_wrapper(
         transaction_from_db,
         repo,
         valid_internal_transactions,
         transaction_hash,
         json_rpc_named_arguments,
         transaction_hashes,
         transaction_hashes_iterator,
         timeout,
         timestamps,
         first_trace
       ) do
    cond do
      !transaction_from_db ->
        transaction_receipt_from_node = fetch_transaction_receipt_from_node(transaction_hash, json_rpc_named_arguments)

        update_transactions_inner(
          repo,
          valid_internal_transactions,
          transaction_hashes,
          transaction_hashes_iterator,
          timeout,
          timestamps,
          first_trace,
          transaction_from_db,
          transaction_receipt_from_node
        )

      transaction_from_db && Map.get(transaction_from_db, :cumulative_gas_used) ->
        update_transactions_inner(
          repo,
          valid_internal_transactions,
          transaction_hashes,
          transaction_hashes_iterator,
          timeout,
          timestamps,
          first_trace,
          transaction_from_db
        )

      true ->
        transaction_receipt_from_node = fetch_transaction_receipt_from_node(transaction_hash, json_rpc_named_arguments)

        update_transactions_inner(
          repo,
          valid_internal_transactions,
          transaction_hashes,
          transaction_hashes_iterator,
          timeout,
          timestamps,
          first_trace,
          transaction_from_db,
          transaction_receipt_from_node
        )
    end
  end

  defp get_trivial_transaction_hashes_with_error_in_internal_transaction(internal_transactions) do
    internal_transactions
    |> Enum.filter(fn internal_transaction ->
      internal_transaction[:index] != 0 && !is_nil(internal_transaction[:error])
    end)
    |> Enum.map(fn internal_transaction -> internal_transaction[:transaction_hash] end)
    |> MapSet.new()
  end

  defp fetch_transaction_receipt_from_node(transaction_hash, json_rpc_named_arguments) do
    receipt_response =
      EthereumJSONRPC.fetch_transaction_receipts(
        [
          %{
            :hash => to_string(transaction_hash),
            :gas => 0
          }
        ],
        json_rpc_named_arguments
      )

    case receipt_response do
      {:ok,
       %{
         :receipts => [
           receipt
         ]
       }} ->
        receipt

      _ ->
        %{:cumulative_gas_used => nil}
    end
  end

  # credo:disable-for-next-line
  defp update_transactions_inner(
         repo,
         valid_internal_transactions,
         transaction_hashes,
         transaction_hashes_iterator,
         timeout,
         timestamps,
         first_trace,
         transaction_from_db,
         transaction_receipt_from_node \\ nil
       ) do
    valid_internal_transactions_count = Enum.count(valid_internal_transactions)

    transactions_with_error_in_internal_transactions =
      get_trivial_transaction_hashes_with_error_in_internal_transaction(valid_internal_transactions)

    set =
      generate_transaction_set_to_update(
        first_trace,
        transaction_from_db,
        transaction_receipt_from_node,
        timestamps,
        transactions_with_error_in_internal_transactions
      )

    update_query =
      from(
        t in Transaction,
        where: t.hash == ^first_trace.transaction_hash,
        # ShareLocks order already enforced by `acquire_transactions` (see docs: sharelocks.md)
        update: [
          set: ^set
        ]
      )

    transaction_hashes_iterator = transaction_hashes_iterator + 1

    try do
      {_transaction_count, result} = repo.update_all(update_query, [], timeout: timeout)

      if valid_internal_transactions_count == transaction_hashes_iterator do
        {:halt, result}
      else
        {:cont, transaction_hashes_iterator}
      end
    rescue
      postgrex_error in Postgrex.Error ->
        {:halt, %{exception: postgrex_error, transaction_hashes: transaction_hashes}}
    end
  end

  def generate_transaction_set_to_update(
        first_trace,
        transaction_from_db,
        transaction_receipt_from_node,
        timestamps,
        transactions_with_error_in_internal_transactions
      ) do
    default_set = [
      created_contract_address_hash: first_trace.created_contract_address_hash,
      updated_at: timestamps.updated_at
    ]

    # we don't save reverted trace outputs, but if we did, we could also set :revert_reason here
    set =
      default_set
      |> put_status_in_update_set(first_trace, transaction_from_db)
      |> put_error_in_update_set(first_trace, transaction_from_db, transaction_receipt_from_node)
      |> Keyword.put_new(:block_hash, first_trace.block_hash)
      |> Keyword.put_new(:block_number, first_trace.block_number)
      |> Keyword.put_new(:index, transaction_receipt_from_node && transaction_receipt_from_node.transaction_index)
      |> Keyword.put_new(
        :cumulative_gas_used,
        transaction_receipt_from_node && transaction_receipt_from_node.cumulative_gas_used
      )
      |> Keyword.put_new(
        :has_error_in_internal_transactions,
        if(Enum.member?(transactions_with_error_in_internal_transactions, first_trace.transaction_hash),
          do: true,
          else: false
        )
      )

    set_with_gas_used =
      if transaction_receipt_from_node && transaction_receipt_from_node.gas_used do
        Keyword.put_new(set, :gas_used, transaction_receipt_from_node.gas_used)
      else
        set
      end

    filtered_set = Enum.reject(set_with_gas_used, fn {_key, value} -> is_nil(value) end)

    filtered_set
  end

  defp put_status_in_update_set(update_set, first_trace, %{status: nil}),
    do: Keyword.put_new(update_set, :status, first_trace.status)

  defp put_status_in_update_set(update_set, _first_trace, _transaction_from_db), do: update_set

  defp put_error_in_update_set(update_set, first_trace, _transaction_from_db, %{status: :error}),
    do: Keyword.put_new(update_set, :error, first_trace.error)

  defp put_error_in_update_set(update_set, first_trace, %{status: :error}, _transaction_receipt_from_node),
    do: Keyword.put_new(update_set, :error, first_trace.error)

  defp put_error_in_update_set(update_set, first_trace, _transaction_from_db, _transaction_receipt_from_node) do
    case update_set[:status] do
      :error -> Keyword.put_new(update_set, :error, first_trace.error)
      _ -> update_set
    end
  end

  defp set_refetch_needed_for_invalid_blocks(repo, invalid_block_numbers, %{updated_at: updated_at}) do
    if Enum.empty?(invalid_block_numbers) do
      {:ok, []}
    else
      update_block_query =
        from(
          block in Block,
          where: block.number in ^invalid_block_numbers and block.consensus == true,
          where: ^traceable_blocks_dynamic_query(),
          select: block.hash,
          # ShareLocks order already enforced by `acquire_blocks` (see docs: sharelocks.md)
          update: [set: [refetch_needed: true, updated_at: ^updated_at]]
        )

      try do
        {_num, result} = repo.update_all(update_block_query, [])
        MissingRangesManipulator.add_ranges_by_block_numbers(invalid_block_numbers)

        Logger.debug(fn ->
          [
            "consensus removed from blocks with numbers: ",
            inspect(invalid_block_numbers),
            " because of mismatching transactions"
          ]
        end)

        {:ok, result}
      rescue
        postgrex_error in Postgrex.Error ->
          {:error, %{exception: postgrex_error, invalid_block_numbers: invalid_block_numbers}}
      end
    end
  end

  def update_pending_blocks_status(repo, pending_hashes, invalid_block_hashes) do
    delete_query =
      case pending_hashes do
        {:block_hashes, block_hashes} ->
          valid_block_hashes =
            block_hashes
            |> MapSet.new()
            |> MapSet.difference(MapSet.new(invalid_block_hashes))
            |> MapSet.to_list()

          PendingOperationsHelper.block_hash_in_query(valid_block_hashes)

        {:transaction_hashes, transaction_hashes} ->
          from(
            pending_ops in PendingTransactionOperation,
            where: pending_ops.transaction_hash in ^transaction_hashes
          )
      end

    try do
      # ShareLocks order already enforced by `acquire_pending_internal_transactions` (see docs: sharelocks.md)
      {_count, deleted} = repo.delete_all(delete_query, [])

      {:ok, deleted}
    rescue
      postgrex_error in Postgrex.Error ->
        {:error, %{exception: postgrex_error, pending_hashes: pending_hashes}}
    end
  end

  defp traceable_blocks_dynamic_query do
    if RangesHelper.trace_ranges_present?() do
      block_ranges = RangesHelper.get_trace_block_ranges()

      Enum.reduce(block_ranges, dynamic([_], false), fn
        _from.._to//_ = range, acc -> dynamic([block], ^acc or block.number in ^range)
        num_to_latest, acc -> dynamic([block], ^acc or block.number >= ^num_to_latest)
      end)
    else
      dynamic([_], true)
    end
  end
end
