defmodule Explorer.Chain.Data do
  @moduledoc """
  The Elixir-native representation of `t:EthereumJSONRPC.data/0`.

  `t:EthereumJSONRPC.data/0` is an unpadded hexadecimal number with 0 or more digits.  Each pair of digits maps directly
  to a byte in the underlying binary representation.  When interpreted as a number, it should be treated as big-endian.
  """

  alias Explorer.Chain.Data
  alias Poison.Encoder.BitString

  use Ecto.Type

  @typedoc """
  A variable-byte-length binary, wrapped in a struct, so that it can use protocols.
  """
  @type t :: %Data{bytes: <<_::_*8>>}

  defstruct ~w(bytes)a

  @doc """
  Converts the `t:t/0` to `iodata` representation written efficiently to users.

      iex> %Explorer.Chain.Data{
      ...>   bytes: <<>>
      ...> } |>
      ...> Explorer.Chain.Data.to_iodata() |>
      ...> IO.iodata_to_binary()
      "0x"
      iex> %Explorer.Chain.Data{
      ...>   bytes: <<0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 134, 45, 103, 203, 7,
      ...>     115, 238, 63, 140, 231, 234, 137, 179, 40, 255, 234, 134, 26,
      ...>     179, 239>>
      ...> } |>
      ...> Explorer.Chain.Data.to_iodata() |>
      ...> IO.iodata_to_binary()
      "0x000000000000000000000000862d67cb0773ee3f8ce7ea89b328ffea861ab3ef"

  """
  @spec to_iodata(t) :: iodata()
  def to_iodata(%Data{bytes: bytes}) do
    ["0x", Base.encode16(bytes, case: :lower)]
  end

  @doc """
  Converts the `t:t/0` to string representation shown to users.

      iex> Explorer.Chain.Data.to_string(
      ...>   %Explorer.Chain.Data{
      ...>     bytes: <<>>
      ...>   }
      ...> )
      "0x"
      iex> Explorer.Chain.Data.to_string(
      ...>   %Explorer.Chain.Data{
      ...>     bytes: <<0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 134, 45, 103, 203, 7,
      ...>       115, 238, 63, 140, 231, 234, 137, 179, 40, 255, 234, 134, 26,
      ...>       179, 239>>
      ...>   }
      ...> )
      "0x000000000000000000000000862d67cb0773ee3f8ce7ea89b328ffea861ab3ef"

  """
  @spec to_string(t) :: String.t()
  def to_string(%Data{} = data) do
    data
    |> to_iodata()
    |> IO.iodata_to_binary()
  end

  def to_string(nil), do: "0x"

  @doc """
  Casts `term` to `t:t/0`.

  An empty `t:t/0` will pass through unchanged

      iex> Explorer.Chain.Data.cast(%Explorer.Chain.Data{bytes: <<>>})
      {:ok, %Explorer.Chain.Data{bytes: <<>>}}

  An empty `t:t/0` is presented as `0x` in Ethereum JSONRPC.

      iex> Explorer.Chain.Data.cast("0x")
      {:ok, %Explorer.Chain.Data{bytes: <<>>}}

  Hashes can be represented as `Explorer.Chain.Data`, but it is better to use `Explorer.Chain.Hash.Full` or
  `Explorer.Chain.Hash.Address`.

      iex> Explorer.Chain.Data.cast("0x9fc76417374aa880d4449a1f7f31ec597f00b1f6f3dd2d66f4c9c6c445836d8b")
      {
        :ok,
        %Explorer.Chain.Data{
          bytes: <<0x9fc76417374aa880d4449a1f7f31ec597f00b1f6f3dd2d66f4c9c6c445836d8b :: big-integer-size(32)-unit(8)>>
        }
      }
      iex> Explorer.Chain.Data.cast("0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed")
      {
        :ok,
        %Explorer.Chain.Data{
          bytes: <<0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed :: big-integer-size(20)-unit(8)>>
        }
      }

  Input to transactions can be represented as `Explorer.Chain.Data`

      iex> Explorer.Chain.Data.cast("0x6060604052341561000f57600080fd5b336000806101000a81548173ffffffffffffffffffffffffffffffffffffffff021916908373ffffffffffffffffffffffffffffffffffffffff1602179055506102db8061005e6000396000f300606060405260043610610062576000357c0100000000000000000000000000000000000000000000000000000000900463ffffffff1680630900f01014610067578063445df0ac146100a05780638da5cb5b146100c9578063fdacd5761461011e575b600080fd5b341561007257600080fd5b61009e600480803573ffffffffffffffffffffffffffffffffffffffff16906020019091905050610141565b005b34156100ab57600080fd5b6100b3610224565b6040518082815260200191505060405180910390f35b34156100d457600080fd5b6100dc61022a565b604051808273ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff16815260200191505060405180910390f35b341561012957600080fd5b61013f600480803590602001909190505061024f565b005b60008060009054906101000a900473ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff163373ffffffffffffffffffffffffffffffffffffffff161415610220578190508073ffffffffffffffffffffffffffffffffffffffff1663fdacd5766001546040518263ffffffff167c010000000000000000000000000000000000000000000000000000000002815260040180828152602001915050600060405180830381600087803b151561020b57600080fd5b6102c65a03f1151561021c57600080fd5b5050505b5050565b60015481565b6000809054906101000a900473ffffffffffffffffffffffffffffffffffffffff1681565b6000809054906101000a900473ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff163373ffffffffffffffffffffffffffffffffffffffff1614156102ac57806001819055505b505600a165627a7a72305820a9c628775efbfbc17477a472413c01ee9b33881f550c59d21bee9928835c854b0029")
      {
        :ok,
        %Explorer.Chain.Data{
          bytes: <<96, 96, 96, 64, 82, 52, 21, 97, 0, 15, 87, 96, 0, 128, 253, 91, 51,
             96, 0, 128, 97, 1, 0, 10, 129, 84, 129, 115, 255, 255, 255, 255, 255, 255,
             255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 2,
             25, 22, 144, 131, 115, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
             255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 22, 2, 23, 144, 85, 80,
             97, 2, 219, 128, 97, 0, 94, 96, 0, 57, 96, 0, 243, 0, 96, 96, 96, 64, 82,
             96, 4, 54, 16, 97, 0, 98, 87, 96, 0, 53, 124, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0,
             0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 144, 4, 99, 255,
             255, 255, 255, 22, 128, 99, 9, 0, 240, 16, 20, 97, 0, 103, 87, 128, 99, 68,
             93, 240, 172, 20, 97, 0, 160, 87, 128, 99, 141, 165, 203, 91, 20, 97, 0,
             201, 87, 128, 99, 253, 172, 213, 118, 20, 97, 1, 30, 87, 91, 96, 0, 128,
             253, 91, 52, 21, 97, 0, 114, 87, 96, 0, 128, 253, 91, 97, 0, 158, 96, 4,
             128, 128, 53, 115, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
             255, 255, 255, 255, 255, 255, 255, 255, 255, 22, 144, 96, 32, 1, 144, 145,
             144, 80, 80, 97, 1, 65, 86, 91, 0, 91, 52, 21, 97, 0, 171, 87, 96, 0, 128,
             253, 91, 97, 0, 179, 97, 2, 36, 86, 91, 96, 64, 81, 128, 130, 129, 82, 96,
             32, 1, 145, 80, 80, 96, 64, 81, 128, 145, 3, 144, 243, 91, 52, 21, 97, 0,
             212, 87, 96, 0, 128, 253, 91, 97, 0, 220, 97, 2, 42, 86, 91, 96, 64, 81,
             128, 130, 115, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
             255, 255, 255, 255, 255, 255, 255, 255, 22, 115, 255, 255, 255, 255, 255,
             255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
             22, 129, 82, 96, 32, 1, 145, 80, 80, 96, 64, 81, 128, 145, 3, 144, 243, 91,
             52, 21, 97, 1, 41, 87, 96, 0, 128, 253, 91, 97, 1, 63, 96, 4, 128, 128, 53,
             144, 96, 32, 1, 144, 145, 144, 80, 80, 97, 2, 79, 86, 91, 0, 91, 96, 0,
             128, 96, 0, 144, 84, 144, 97, 1, 0, 10, 144, 4, 115, 255, 255, 255, 255,
             255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
             255, 22, 115, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
             255, 255, 255, 255, 255, 255, 255, 255, 22, 51, 115, 255, 255, 255, 255,
             255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
             255, 22, 20, 21, 97, 2, 32, 87, 129, 144, 80, 128, 115, 255, 255, 255, 255,
             255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
             255, 22, 99, 253, 172, 213, 118, 96, 1, 84, 96, 64, 81, 130, 99, 255, 255,
             255, 255, 22, 124, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
             0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 129, 82, 96, 4, 1, 128, 130, 129, 82, 96,
             32, 1, 145, 80, 80, 96, 0, 96, 64, 81, 128, 131, 3, 129, 96, 0, 135, 128,
             59, 21, 21, 97, 2, 11, 87, 96, 0, 128, 253, 91, 97, 2, 198, 90, 3, 241, 21,
             21, 97, 2, 28, 87, 96, 0, 128, 253, 91, 80, 80, 80, 91, 80, 80, 86, 91, 96,
             1, 84, 129, 86, 91, 96, 0, 128, 144, 84, 144, 97, 1, 0, 10, 144, 4, 115,
             255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
             255, 255, 255, 255, 255, 22, 129, 86, 91, 96, 0, 128, 144, 84, 144, 97, 1,
             0, 10, 144, 4, 115, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
             255, 255, 255, 255, 255, 255, 255, 255, 255, 22, 115, 255, 255, 255, 255,
             255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
             255, 22, 51, 115, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
             255, 255, 255, 255, 255, 255, 255, 255, 255, 22, 20, 21, 97, 2, 172, 87,
             128, 96, 1, 129, 144, 85, 80, 91, 80, 86, 0, 161, 101, 98, 122, 122, 114,
             48, 88, 32, 169, 198, 40, 119, 94, 251, 251, 193, 116, 119, 164, 114, 65,
             60, 1, 238, 155, 51, 136, 31, 85, 12, 89, 210, 27, 238, 153, 40, 131, 92,
             133, 75, 0, 41>>
          }
      }

  The public key of the signer of a transaction can be represented as `Explorer.Chain.Data`.

      iex> Explorer.Chain.Data.cast("0xe5d196ad4ceada719d9e592f7166d0c75700f6eab2e3c3de34ba751ea786527cb3f6eb96ad9fdfdb9989ff572df50f1c42ef800af9c5207a38b929aff969b5c9")
      {
        :ok,
        %Explorer.Chain.Data{
          bytes: <<229, 209, 150, 173, 76, 234, 218, 113, 157, 158, 89, 47, 113, 102,
             208, 199, 87, 0, 246, 234, 178, 227, 195, 222, 52, 186, 117, 30, 167, 134,
             82, 124, 179, 246, 235, 150, 173, 159, 223, 219, 153, 137, 255, 87, 45,
             245, 15, 28, 66, 239, 128, 10, 249, 197, 32, 122, 56, 185, 41, 175, 249,
             105, 181, 201>>
        }
      }

  Log data can be represented as `Explorer.Chain.Data`.

      iex> Explorer.Chain.Data.cast("0x000000000000000000000000862d67cb0773ee3f8ce7ea89b328ffea861ab3ef")
      {:ok,
       %Explorer.Chain.Data{
         bytes: <<0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 134, 45, 103, 203, 7,
           115, 238, 63, 140, 231, 234, 137, 179, 40, 255, 234, 134, 26,
           179, 239>>
       }}

  The init argument to create the contract and the created contract code can be represented as `Explorer.Chain.Data`.

      iex> Explorer.Chain.Data.cast("0x6060604052341561000f57600080fd5b336000806101000a81548173ffffffffffffffffffffffffffffffffffffffff021916908373ffffffffffffffffffffffffffffffffffffffff1602179055506102db8061005e6000396000f300606060405260043610610062576000357c0100000000000000000000000000000000000000000000000000000000900463ffffffff1680630900f01014610067578063445df0ac146100a05780638da5cb5b146100c9578063fdacd5761461011e575b600080fd5b341561007257600080fd5b61009e600480803573ffffffffffffffffffffffffffffffffffffffff16906020019091905050610141565b005b34156100ab57600080fd5b6100b3610224565b6040518082815260200191505060405180910390f35b34156100d457600080fd5b6100dc61022a565b604051808273ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff16815260200191505060405180910390f35b341561012957600080fd5b61013f600480803590602001909190505061024f565b005b60008060009054906101000a900473ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff163373ffffffffffffffffffffffffffffffffffffffff161415610220578190508073ffffffffffffffffffffffffffffffffffffffff1663fdacd5766001546040518263ffffffff167c010000000000000000000000000000000000000000000000000000000002815260040180828152602001915050600060405180830381600087803b151561020b57600080fd5b6102c65a03f1151561021c57600080fd5b5050505b5050565b60015481565b6000809054906101000a900473ffffffffffffffffffffffffffffffffffffffff1681565b6000809054906101000a900473ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff163373ffffffffffffffffffffffffffffffffffffffff1614156102ac57806001819055505b505600a165627a7a72305820a9c628775efbfbc17477a472413c01ee9b33881f550c59d21bee9928835c854b0029")
      {:ok,
       %Explorer.Chain.Data{
        bytes: <<96, 96, 96, 64, 82, 52, 21, 97, 0, 15, 87, 96, 0, 128, 253, 91, 51,
          96, 0, 128, 97, 1, 0, 10, 129, 84, 129, 115, 255, 255, 255, 255, 255, 255,
          255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 2,
          25, 22, 144, 131, 115, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
          255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 22, 2, 23, 144, 85, 80,
          97, 2, 219, 128, 97, 0, 94, 96, 0, 57, 96, 0, 243, 0, 96, 96, 96, 64, 82,
          96, 4, 54, 16, 97, 0, 98, 87, 96, 0, 53, 124, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0,
          0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 144, 4, 99, 255,
          255, 255, 255, 22, 128, 99, 9, 0, 240, 16, 20, 97, 0, 103, 87, 128, 99, 68,
          93, 240, 172, 20, 97, 0, 160, 87, 128, 99, 141, 165, 203, 91, 20, 97, 0,
          201, 87, 128, 99, 253, 172, 213, 118, 20, 97, 1, 30, 87, 91, 96, 0, 128,
          253, 91, 52, 21, 97, 0, 114, 87, 96, 0, 128, 253, 91, 97, 0, 158, 96, 4,
          128, 128, 53, 115, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
          255, 255, 255, 255, 255, 255, 255, 255, 255, 22, 144, 96, 32, 1, 144, 145,
          144, 80, 80, 97, 1, 65, 86, 91, 0, 91, 52, 21, 97, 0, 171, 87, 96, 0, 128,
          253, 91, 97, 0, 179, 97, 2, 36, 86, 91, 96, 64, 81, 128, 130, 129, 82, 96,
          32, 1, 145, 80, 80, 96, 64, 81, 128, 145, 3, 144, 243, 91, 52, 21, 97, 0,
          212, 87, 96, 0, 128, 253, 91, 97, 0, 220, 97, 2, 42, 86, 91, 96, 64, 81,
          128, 130, 115, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
          255, 255, 255, 255, 255, 255, 255, 255, 22, 115, 255, 255, 255, 255, 255,
          255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
          22, 129, 82, 96, 32, 1, 145, 80, 80, 96, 64, 81, 128, 145, 3, 144, 243, 91,
          52, 21, 97, 1, 41, 87, 96, 0, 128, 253, 91, 97, 1, 63, 96, 4, 128, 128, 53,
          144, 96, 32, 1, 144, 145, 144, 80, 80, 97, 2, 79, 86, 91, 0, 91, 96, 0,
          128, 96, 0, 144, 84, 144, 97, 1, 0, 10, 144, 4, 115, 255, 255, 255, 255,
          255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
          255, 22, 115, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
          255, 255, 255, 255, 255, 255, 255, 255, 22, 51, 115, 255, 255, 255, 255,
          255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
          255, 22, 20, 21, 97, 2, 32, 87, 129, 144, 80, 128, 115, 255, 255, 255, 255,
          255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
          255, 22, 99, 253, 172, 213, 118, 96, 1, 84, 96, 64, 81, 130, 99, 255, 255,
          255, 255, 22, 124, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
          0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 129, 82, 96, 4, 1, 128, 130, 129, 82, 96,
          32, 1, 145, 80, 80, 96, 0, 96, 64, 81, 128, 131, 3, 129, 96, 0, 135, 128,
          59, 21, 21, 97, 2, 11, 87, 96, 0, 128, 253, 91, 97, 2, 198, 90, 3, 241, 21,
          21, 97, 2, 28, 87, 96, 0, 128, 253, 91, 80, 80, 80, 91, 80, 80, 86, 91, 96,
          1, 84, 129, 86, 91, 96, 0, 128, 144, 84, 144, 97, 1, 0, 10, 144, 4, 115,
          255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
          255, 255, 255, 255, 255, 22, 129, 86, 91, 96, 0, 128, 144, 84, 144, 97, 1,
          0, 10, 144, 4, 115, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
          255, 255, 255, 255, 255, 255, 255, 255, 255, 22, 115, 255, 255, 255, 255,
          255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
          255, 22, 51, 115, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
          255, 255, 255, 255, 255, 255, 255, 255, 255, 22, 20, 21, 97, 2, 172, 87,
          128, 96, 1, 129, 144, 85, 80, 91, 80, 86, 0, 161, 101, 98, 122, 122, 114,
          48, 88, 32, 169, 198, 40, 119, 94, 251, 251, 193, 116, 119, 164, 114, 65,
          60, 1, 238, 155, 51, 136, 31, 85, 12, 89, 210, 27, 238, 153, 40, 131, 92,
          133, 75, 0, 41>>
       }}
      iex> Explorer.Chain.Data.cast("0x606060405260043610610062576000357c0100000000000000000000000000000000000000000000000000000000900463ffffffff1680630900f01014610067578063445df0ac146100a05780638da5cb5b146100c9578063fdacd5761461011e575b600080fd5b341561007257600080fd5b61009e600480803573ffffffffffffffffffffffffffffffffffffffff16906020019091905050610141565b005b34156100ab57600080fd5b6100b3610224565b6040518082815260200191505060405180910390f35b34156100d457600080fd5b6100dc61022a565b604051808273ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff16815260200191505060405180910390f35b341561012957600080fd5b61013f600480803590602001909190505061024f565b005b60008060009054906101000a900473ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff163373ffffffffffffffffffffffffffffffffffffffff161415610220578190508073ffffffffffffffffffffffffffffffffffffffff1663fdacd5766001546040518263ffffffff167c010000000000000000000000000000000000000000000000000000000002815260040180828152602001915050600060405180830381600087803b151561020b57600080fd5b6102c65a03f1151561021c57600080fd5b5050505b5050565b60015481565b6000809054906101000a900473ffffffffffffffffffffffffffffffffffffffff1681565b6000809054906101000a900473ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff163373ffffffffffffffffffffffffffffffffffffffff1614156102ac57806001819055505b505600a165627a7a72305820a9c628775efbfbc17477a472413c01ee9b33881f550c59d21bee9928835c854b0029")
      {:ok,
       %Explorer.Chain.Data{
        bytes: <<96, 96, 96, 64, 82, 96, 4, 54, 16, 97, 0, 98, 87, 96, 0, 53, 124, 1,
          0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
          0, 0, 0, 144, 4, 99, 255, 255, 255, 255, 22, 128, 99, 9, 0, 240, 16, 20,
          97, 0, 103, 87, 128, 99, 68, 93, 240, 172, 20, 97, 0, 160, 87, 128, 99,
          141, 165, 203, 91, 20, 97, 0, 201, 87, 128, 99, 253, 172, 213, 118, 20, 97,
          1, 30, 87, 91, 96, 0, 128, 253, 91, 52, 21, 97, 0, 114, 87, 96, 0, 128,
          253, 91, 97, 0, 158, 96, 4, 128, 128, 53, 115, 255, 255, 255, 255, 255,
          255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
          22, 144, 96, 32, 1, 144, 145, 144, 80, 80, 97, 1, 65, 86, 91, 0, 91, 52,
          21, 97, 0, 171, 87, 96, 0, 128, 253, 91, 97, 0, 179, 97, 2, 36, 86, 91, 96,
          64, 81, 128, 130, 129, 82, 96, 32, 1, 145, 80, 80, 96, 64, 81, 128, 145, 3,
          144, 243, 91, 52, 21, 97, 0, 212, 87, 96, 0, 128, 253, 91, 97, 0, 220, 97,
          2, 42, 86, 91, 96, 64, 81, 128, 130, 115, 255, 255, 255, 255, 255, 255,
          255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 22,
          115, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
          255, 255, 255, 255, 255, 255, 22, 129, 82, 96, 32, 1, 145, 80, 80, 96, 64,
          81, 128, 145, 3, 144, 243, 91, 52, 21, 97, 1, 41, 87, 96, 0, 128, 253, 91,
          97, 1, 63, 96, 4, 128, 128, 53, 144, 96, 32, 1, 144, 145, 144, 80, 80, 97,
          2, 79, 86, 91, 0, 91, 96, 0, 128, 96, 0, 144, 84, 144, 97, 1, 0, 10, 144,
          4, 115, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
          255, 255, 255, 255, 255, 255, 255, 22, 115, 255, 255, 255, 255, 255, 255,
          255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 22,
          51, 115, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
          255, 255, 255, 255, 255, 255, 255, 22, 20, 21, 97, 2, 32, 87, 129, 144, 80,
          128, 115, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
          255, 255, 255, 255, 255, 255, 255, 22, 99, 253, 172, 213, 118, 96, 1, 84,
          96, 64, 81, 130, 99, 255, 255, 255, 255, 22, 124, 1, 0, 0, 0, 0, 0, 0, 0,
          0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 129, 82,
          96, 4, 1, 128, 130, 129, 82, 96, 32, 1, 145, 80, 80, 96, 0, 96, 64, 81,
          128, 131, 3, 129, 96, 0, 135, 128, 59, 21, 21, 97, 2, 11, 87, 96, 0, 128,
          253, 91, 97, 2, 198, 90, 3, 241, 21, 21, 97, 2, 28, 87, 96, 0, 128, 253,
          91, 80, 80, 80, 91, 80, 80, 86, 91, 96, 1, 84, 129, 86, 91, 96, 0, 128,
          144, 84, 144, 97, 1, 0, 10, 144, 4, 115, 255, 255, 255, 255, 255, 255, 255,
          255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 22, 129,
          86, 91, 96, 0, 128, 144, 84, 144, 97, 1, 0, 10, 144, 4, 115, 255, 255, 255,
          255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
          255, 255, 22, 115, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
          255, 255, 255, 255, 255, 255, 255, 255, 255, 22, 51, 115, 255, 255, 255,
          255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
          255, 255, 22, 20, 21, 97, 2, 172, 87, 128, 96, 1, 129, 144, 85, 80, 91, 80,
          86, 0, 161, 101, 98, 122, 122, 114, 48, 88, 32, 169, 198, 40, 119, 94, 251,
          251, 193, 116, 119, 164, 114, 65, 60, 1, 238, 155, 51, 136, 31, 85, 12, 89,
          210, 27, 238, 153, 40, 131, 92, 133, 75, 0, 41>>
       }}

  A hexadecimal number MUST be
  [byte](https://en.wikipedia.org/wiki/Byte)-[aligned](https://en.wikipedia.org/wiki/Data_structure_alignment).  If it
  has an odd number of digits, then it is only [nibble](https://en.wikipedia.org/wiki/Nibble)-aligned and can't a
  valid `t:EthereumJSONRPC.data/0`, which MUST be in bytes.

      iex> Explorer.Chain.Data.cast("0xF")
      :error

  """
  @impl Ecto.Type
  @spec cast(term()) :: {:ok, t()} | :error

  def cast("0x" <> rest) do
    with {:ok, bytes} <- Base.decode16(rest, case: :mixed) do
      {:ok, %Data{bytes: bytes}}
    end
  end

  def cast(%Data{} = data), do: {:ok, data}
  def cast(_), do: :error

  @doc """
  Dumps the binary data to `:binary` (`bytea`) format used in database.

  If the field from the struct is `t:t/0`, then it succeeds.

      iex> Explorer.Chain.Data.dump(
      ...>   %Explorer.Chain.Data{
      ...>     bytes: <<>>
      ...>   }
      ...> )
      {:ok, <<>>}

  If the field is from a different struct, `:error` is returned.

      iex> Explorer.Chain.Data.dump(
      ...>   %Explorer.Chain.Hash{
      ...>     byte_count: 20,
      ...>     bytes: <<0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed :: big-integer-size(20)-unit(8)>>
      ...>   }
      ...> )
      :error

  """
  @impl Ecto.Type
  @spec dump(term()) :: {:ok, binary()} | :error
  def dump(%Data{bytes: bytes}), do: {:ok, bytes}
  def dump(_), do: :error

  @doc """
  Loads the binary data from the database.

      iex> Explorer.Chain.Data.load(<<>>)
      {:ok, %Explorer.Chain.Data{bytes: <<>>}}

  `EthereumJSONRPC.data/0` that has been converted to an integer cannot be loaded

      iex> Explorer.Chain.Data.load(0)
      :error

  """
  @impl Ecto.Type
  @spec load(term()) :: {:ok, t()} | :error
  def load(<<_::binary>> = bytes), do: {:ok, %Data{bytes: bytes}}
  def load(_), do: :error

  @doc """
  The underlying database type: `:binary`.
  """
  @impl Ecto.Type
  @spec type() :: :binary
  def type, do: :binary

  @doc """
    Determines if a data is just an empty binary (0x).

    ## Parameters
      - `Data.t()`

    ## Returns
      - `true` if the data is empty (0x)
      - `false` if data contains bytecode or is not a valid Data struct
      - `nil` if the data is not a Data struct

    ## Example
        iex> Explorer.Chain.Data.empty?(%Explorer.Chain.Data{bytes: <<>>})
        true

        iex> Explorer.Chain.Data.empty?(%Explorer.Chain.Data{bytes: <<1, 2, 3>>})
        false

        iex> Explorer.Chain.Data.empty?(<<>>)
        nil
  """
  @spec empty?(any()) :: boolean() | nil
  def empty?(%Data{bytes: <<>>}), do: true
  def empty?(%Data{bytes: _}), do: false
  def empty?(_), do: nil

  defimpl String.Chars do
    @doc """
    Converts the `#{@for}:t/0` to string representation shown to users.

        iex> to_string(
        ...>   %Explorer.Chain.Data{
        ...>     bytes: <<>>
        ...>   }
        ...> )
        "0x"
        iex> to_string(
        ...>   %Explorer.Chain.Data{
        ...>     bytes: <<0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 134, 45, 103, 203, 7,
        ...>       115, 238, 63, 140, 231, 234, 137, 179, 40, 255, 234, 134, 26,
        ...>       179, 239>>
        ...>   }
        ...> )
        "0x000000000000000000000000862d67cb0773ee3f8ce7ea89b328ffea861ab3ef"

    """
    def to_string(data) do
      @for.to_string(data)
    end
  end

  defimpl Poison.Encoder do
    def encode(data, options) do
      data
      |> to_string()
      |> BitString.encode(options)
    end
  end

  defimpl Jason.Encoder do
    alias Jason.Encode

    def encode(data, opts) do
      data
      |> to_string()
      |> Encode.string(opts)
    end
  end
end
