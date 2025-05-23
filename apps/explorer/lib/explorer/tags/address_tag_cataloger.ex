defmodule Explorer.Tags.AddressTag.Cataloger do
  @moduledoc """
  Actualizes address tags.
  """

  use GenServer, restart: :transient

  alias Explorer.Chain.Fetcher.FetchValidatorInfoOnDemand
  alias Explorer.EnvVarTranslator
  alias Explorer.Tags.{AddressTag, AddressToTag}
  alias Explorer.Validator.MetadataRetriever

  def start_link(_) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @impl GenServer
  def init(args) do
    send(self(), :fetch_tags)

    {:ok, args}
  end

  @impl GenServer
  def handle_info(:fetch_tags, state) do
    create_new_tags()

    send(self(), :bind_addresses)

    {:noreply, state}
  end

  def handle_info(:bind_addresses, state) do
    # set validator tag
    set_validator_tag()

    # set amb bridge mediators tag
    set_amb_mediators_tag()

    # set omni bridge tag
    set_omni_tag()

    # set L2 tag
    set_l2_tag()

    all_tags = AddressTag.get_all()

    all_tags
    |> Enum.each(fn %{label: tag_name} ->
      if tag_name !== "validator" && tag_name !== "amb bridge mediators" && tag_name !== "omni bridge" &&
           tag_name !== "l2" && !String.contains?(tag_name, "chainlink") do
        env_var_name = "CUSTOM_CONTRACT_ADDRESSES_#{tag_name_to_env_var_part(tag_name)}"
        set_tag_for_env_var_multiple_addresses(env_var_name, tag_name)
      end
    end)

    {:stop, :normal, state}
  end

  defp tag_name_to_env_var_part(tag_name) do
    tag_name
    |> String.upcase()
    |> String.replace(" ", "_")
    |> String.replace(".", "_")
  end

  defp set_tag_for_multiple_env_var_addresses(env_vars, tag) do
    addresses =
      env_vars
      |> Enum.map(fn env_var ->
        env_var
        |> System.get_env("")
        |> String.downcase()
      end)

    tag_id = AddressTag.get_id_by_label(tag)
    AddressToTag.set_tag_to_addresses(tag_id, addresses)
  end

  defp set_tag_for_multiple_env_var_array_addresses(env_vars, tag) do
    addresses =
      env_vars
      |> Enum.reduce([], fn env_var, acc ->
        env_var
        |> System.get_env("")
        |> String.split(",")
        |> Enum.reduce(acc, fn env_var, acc_inner ->
          addr =
            env_var
            |> String.downcase()

          [addr | acc_inner]
        end)
      end)

    tag_id = AddressTag.get_id_by_label(tag)
    AddressToTag.set_tag_to_addresses(tag_id, addresses)
  end

  defp create_new_tags do
    tags = EnvVarTranslator.map_array_env_var_to_list(:new_tags)

    tags
    |> Enum.each(fn %{tag: tag_name, title: tag_display_name} ->
      AddressTag.set(tag_name, tag_display_name)
    end)
  end

  defp set_tag_for_env_var_multiple_addresses(env_var, tag) do
    addresses = env_var_string_array_to_list(env_var)

    tag_id = AddressTag.get_id_by_label(tag)
    AddressToTag.set_tag_to_addresses(tag_id, addresses)
  end

  defp env_var_string_array_to_list(env_var_array_string) do
    env_var =
      env_var_array_string
      |> System.get_env(nil)

    if env_var do
      env_var
      |> String.split(",")
      |> Enum.map(fn env_var_array_string_item ->
        env_var_array_string_item
        |> String.downcase()
      end)
    else
      []
    end
  end

  defp set_validator_tag do
    validators = MetadataRetriever.fetch_validators_list()
    FetchValidatorInfoOnDemand.trigger_fetch(validators)
    tag_id = AddressTag.get_id_by_label("validator")
    AddressToTag.set_tag_to_addresses(tag_id, validators)
  end

  defp set_amb_mediators_tag do
    set_tag_for_multiple_env_var_array_addresses(
      ["AMB_BRIDGE_MEDIATORS", "CUSTOM_CONTRACT_ADDRESSES_AMB_BRIDGE_MEDIATORS"],
      "amb bridge mediators"
    )
  end

  defp set_omni_tag do
    set_tag_for_multiple_env_var_addresses(
      [
        "BRIDGED_TOKENS_ETH_OMNI_BRIDGE_MEDIATOR",
        "BRIDGED_TOKENS_BSC_OMNI_BRIDGE_MEDIATOR",
        "BRIDGED_TOKENS_POA_OMNI_BRIDGE_MEDIATOR"
      ],
      "omni bridge"
    )
  end

  defp set_l2_tag do
    set_tag_for_multiple_env_var_addresses(["CUSTOM_CONTRACT_ADDRESSES_AOX"], "l2")
  end
end
