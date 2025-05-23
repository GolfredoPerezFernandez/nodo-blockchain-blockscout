defmodule BlockScoutWeb.RecentTransactionsController do
  use BlockScoutWeb, :controller

  import Explorer.Chain.SmartContract, only: [burn_address_hash_string: 0]

  alias Explorer.{Chain, PagingOptions}
  alias Explorer.Chain.{DenormalizationHelper, Hash}
  alias Phoenix.View

  {:ok, burn_address_hash} = Chain.string_to_address_hash(burn_address_hash_string())
  @burn_address_hash burn_address_hash

  def index(conn, _params) do
    if ajax?(conn) do
      recent_transactions =
        Chain.recent_collated_transactions(
          true,
          DenormalizationHelper.extend_block_necessity(
            [
              necessity_by_association: %{
                [created_contract_address: :names] => :optional,
                [from_address: :names] => :optional,
                [to_address: :names] => :optional,
                [created_contract_address: :smart_contract] => :optional,
                [from_address: :smart_contract] => :optional,
                [to_address: :smart_contract] => :optional
              },
              paging_options: %PagingOptions{page_size: 5}
            ],
            :required
          )
        )

      transactions =
        Enum.map(recent_transactions, fn transaction ->
          %{
            transaction_hash: Hash.to_string(transaction.hash),
            transaction_html:
              View.render_to_string(BlockScoutWeb.TransactionView, "_tile.html",
                transaction: transaction,
                burn_address_hash: @burn_address_hash,
                conn: conn
              )
          }
        end)

      json(conn, %{transactions: transactions})
    else
      unprocessable_entity(conn)
    end
  end
end
