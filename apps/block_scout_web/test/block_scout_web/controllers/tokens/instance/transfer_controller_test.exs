defmodule BlockScoutWeb.Tokens.Instance.TransferControllerTest do
  use BlockScoutWeb.ConnCase, async: false

  describe "GET token-transfers/2" do
    test "fetches the instance", %{conn: conn} do
      token = insert(:token, type: "ERC-721")

      contract_address_hash = token.contract_address_hash

      token_id = Decimal.new(10)

      insert(:token_instance,
        token_contract_address_hash: contract_address_hash,
        token_id: token_id
      )

      conn = get(conn, "/token/#{contract_address_hash}/instance/#{token_id}/token-transfers")

      assert %{
               assigns: %{
                 token_instance: %{
                   instance: %{token_contract_address_hash: ^contract_address_hash, token_id: ^token_id}
                 }
               }
             } = conn
    end
  end
end
