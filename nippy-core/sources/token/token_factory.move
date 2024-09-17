module nippy_pool::token_factory {
    use std::option;
    use std::option::Option;
    use std::signer;
    use std::string::{Self, String};
    use std::vector;
    use aptos_framework::account;
    use aptos_framework::event::Self;
    use aptos_framework::fungible_asset::Metadata;
    use aptos_framework::object::{Self, Object};
    use aptos_framework::resource_account;

    use nippy_pool::token_base;
    use nippy_pool::underlying_token_factory::Self;

    friend nippy_pool::pool;
    // friend nippy_pool::flashloan_logic;
    // friend nippy_pool::supply_logic;
    // friend nippy_pool::borrow_logic;
    // friend nippy_pool::bridge_logic;
    // friend nippy_pool::liquidation_logic;


    const ATOKEN_REVISION: u256 = 0x1;
    // error config
    const E_NOT_A_TOKEN_ADMIN: u64 = 1;

    // #[event]
    // struct Initialized has store, drop {
    //     underlying_asset: address,
    //     treasury: address,
    //     a_token_decimals: u8,
    //     a_token_name: String,
    //     a_token_symbol: String,
    // }

    // #[event]
    // struct BalanceTransfer has store, drop{
    //     from: address,
    //     to: address,
    //     value: u256,
    //     index: u256,
    // }

    //
    // Entry Functions
    //
    public(friend) fun create_token(
        signer: &signer,
        name: String,
        symbol: String,
        decimals: u8,
        icon_uri: String,
        project_uri: String,
        underlying_asset: address,
        type_of_token: u8,
    ): address {
        let user_addr = signer::address_of(signer);
        if (!account::exists_at(user_addr)) {
            aptos_framework::aptos_account::create_account(user_addr);
        };
        let token_metadata_address = token_base::create_token(
            signer,
            name,
            symbol,
            decimals,
            icon_uri,
            project_uri,
            underlying_asset,
            type_of_token
        );
        return token_metadata_address
    }

    //
    //  Functions Call between contracts
    //

    public(friend) fun mint(
        caller: address,
        to: address,
        amount: u128,
        metadata_address: address
    ) {
        token_base::mint(caller, to, amount, metadata_address);
    }

    public(friend) fun burn(
        caller: address,
        from: address,
        amount: u128,
        metadata_address: address
    ) {
        token_base::burn(caller, from, amount, metadata_address);
    }


    // public(friend) fun transfer_underlying_to(
    //     from: address , to: address, amount: u256, metadata_address: address
    // ) {
    //     underlying_token_factory::transfer_from(
    //         from,
    //         to,
    //         (amount as u64),
    //         get_underlying_asset_address(metadata_address))
    // }

    //
    //  View functions
    //


    #[view]
    /// Return the address of the managed fungible asset that's created when this module is deployed.
    public fun get_metadata_by_symbol(owner: address, symbol: String): Object<Metadata> {
        let metadata_address =
            object::create_object_address(&owner, *string::bytes(&symbol));
        object::address_to_object<Metadata>(metadata_address)
    }

    #[view]
    public fun token_address(owner: address, symbol: String): address {
        object::create_object_address(&owner, *string::bytes(&symbol))
    }

    #[view]
    public fun asset_metadata(owner: address, symbol: String): Object<Metadata> {
        object::address_to_object<Metadata>(token_address(owner, symbol))
    }


    // #[view]
    // public fun get_underlying_asset_address(token_owner: address, metadata_address: address): address {
    //     let token_data = token_base::get_token_data(token_owner, metadata_address);
    //     token_base::get_underlying_asset(&token_data)
    // }

    #[view]
    public fun get_user_balance_and_supply(owner: address, metadata_address: address): (u256, Option<u128>) {
        token_base::get_user_balance_and_supply(owner, metadata_address)
    }

    // #[view]
    // public fun balance_of(owner: address, metadata_address: address): u256 {
    //     token_base::balance_of(owner, metadata_address)
    // }

    #[view]
    public fun balance_of(owner: address, metadata_address: address): u256 {
        token_base::balance_of(owner, metadata_address)
    }

    // #[view]
    // public fun total_supply(token_owner: address, metadata_address: address): u256 {
    //     token_base::total_supply(token_owner, metadata_address)
    // }

    #[view]
    public fun supply(metadata_address: address): u256 {
        (*option::borrow(&token_base::supply(metadata_address)) as u256)
    }

    #[view]
    public fun maximum(metadata_address: address): Option<u128> {
        token_base::maximum(metadata_address)
    }

    #[view]
    public fun name(metadata_address: address): String {
        token_base::name(metadata_address)
    }

    #[view]
    public fun symbol(metadata_address: address): String {
        token_base::symbol(metadata_address)
    }

    #[view]
    public fun decimals(metadata_address: address): u8 {
        token_base::decimals(metadata_address)
    }
}
