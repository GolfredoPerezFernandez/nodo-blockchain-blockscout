defmodule Indexer.Fetcher.PendingTransaction.Supervisor.Case do
  alias Indexer.Fetcher.PendingTransaction

  def start_supervised!(fetcher_arguments \\ []) when is_list(fetcher_arguments) do
    merged_fetcher_arguments =
      Keyword.merge(
        fetcher_arguments,
        flush_interval: 50,
        max_batch_size: 1,
        max_concurrency: 1
      )

    [merged_fetcher_arguments]
    |> PendingTransaction.Supervisor.child_spec()
    |> ExUnit.Callbacks.start_supervised!()
  end
end
