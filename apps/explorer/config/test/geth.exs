import Config

config :explorer,
  json_rpc_named_arguments: [
    transport: EthereumJSONRPC.Mox,
    transport_options: [],
    variant: EthereumJSONRPC.Geth
  ],
  subscribe_named_arguments: [
    transport: EthereumJSONRPC.Mox,
    transport_options: [],
    variant: EthereumJSONRPC.Geth
  ]
