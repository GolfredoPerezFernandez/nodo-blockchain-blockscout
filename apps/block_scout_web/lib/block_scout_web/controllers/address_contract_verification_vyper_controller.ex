defmodule BlockScoutWeb.AddressContractVerificationVyperController do
  use BlockScoutWeb, :controller

  alias BlockScoutWeb.Controller
  alias Explorer.Chain.SmartContract
  alias Explorer.SmartContract.{CompilerVersion, Vyper.PublisherWorker}

  def new(conn, %{"address_id" => address_hash_string}) do
    if SmartContract.verified_with_full_match?(address_hash_string) do
      address_contract_path =
        conn
        |> address_contract_path(:index, address_hash_string)
        |> Controller.full_path()

      redirect(conn, to: address_contract_path)
    else
      changeset =
        SmartContract.changeset(
          %SmartContract{address_hash: address_hash_string},
          %{}
        )

      compiler_versions =
        case CompilerVersion.fetch_versions(:vyper) do
          {:ok, compiler_versions} ->
            compiler_versions

          {:error, _} ->
            []
        end

      render(conn, "new.html",
        changeset: changeset,
        compiler_versions: compiler_versions,
        address_hash: address_hash_string
      )
    end
  end

  def create(
        conn,
        %{
          "smart_contract" => smart_contract
        }
      ) do
    Que.add(PublisherWorker, {smart_contract["address_hash"], smart_contract, conn})

    send_resp(conn, 204, "")
  end
end
