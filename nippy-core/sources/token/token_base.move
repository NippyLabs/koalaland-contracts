module nippy_pool::token_base {
    use std::option::{Self, Option};
    use std::signer;
    use std::string::{Self, String};
    use aptos_std::smart_table::{Self, SmartTable};
    use aptos_std::string_utils::format2;
    // use aptos_framework::event;
    use aptos_framework::fungible_asset::{Self, BurnRef, Metadata, MintRef, TransferRef};
    use aptos_framework::object::{Self, Object};
    use aptos_framework::primary_fungible_store;


    friend nippy_pool::token_factory;
    // friend nippy_pool::variable_token_factory;

    // /// Only fungible asset metadata owner can make changes.
    const ENOT_OWNER: u64 = 1;
    const E_TOKEN_ALREADY_EXISTS: u64 = 2;
    const E_ACCOUNT_NOT_EXISTS: u64 = 3;
    const E_TOKEN_NOT_EXISTS: u64 = 4;

    // #[event]
    // struct Transfer has store, drop {
    //     from: address,
    //     to: address,
    //     value: u256
    // }

    // #[event]
    // struct Mint has store, drop {
    //     caller: address,
    //     on_behalf_of: address,
    //     value: u256,
    //     balance_increase: u256,
    //     index: u256,
    // }

    // #[event]
    // struct Burn has store, drop {
    //     from: address,
    //     target: address,
    //     value: u256,
    //     balance_increase: u256,
    //     index: u256,
    // }

    // struct UserState has store, copy, drop {
    //     balance: u128,
    // }

    // Map of users address and their state data (key = user_address_atoken_address => UserState)
    // struct UserStateMap has key {
    //     value: SmartTable<String, UserState>,
    // }

    // struct TokenData has store, copy, drop {
    //     underlying_asset: address,
    //     type_of_token: u8,
    //     total_supply: u128
        
    //     // type_of_token = 0 --> SOT
    //     // type_of_token = 1 --> JOT
    // }

    // Atoken metadata_address => underlying token metadata_address
    // struct TokenMap has key {
    //     value: SmartTable<address, TokenData>,
    // }

    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    /// Hold refs to control the minting, transfer and burning of fungible assets.
    struct ManagedFungibleAsset has key {
        mint_ref: MintRef,
        transfer_ref: TransferRef,
        burn_ref: BurnRef,
    }

    // fun init_module(signer: &signer) {
    //     // only_token_admin(signer);
    //     move_to(signer, UserStateMap { value: smart_table::new<String, UserState>() });
    //     move_to(signer, TokenMap { value: smart_table::new<address, TokenData>() })
    // }

    // public fun get_user_state(owner: address ,user: address, token_metadata_address: address): UserState acquires UserStateMap {
    //     let user_state_map = borrow_global<UserStateMap>(owner);
    //     let key = format2(&b"{}_{}", user, token_metadata_address);
    //     if (!smart_table::contains(&user_state_map.value, key)) {
    //         return UserState { balance: 0 }
    //     };
    //     *smart_table::borrow(&user_state_map.value, key)
    // }

    // fun set_user_state(
    //     owner: address, user: address, token_metadata_address: address, balance: u128
    // ) acquires UserStateMap {
    //     let user_state_map = borrow_global_mut<UserStateMap>(owner);
    //     let key = format2(&b"{}_{}", user, token_metadata_address);
    //     if (!smart_table::contains(&user_state_map.value, key)) {
    //         smart_table::upsert(&mut user_state_map.value, key,
    //             UserState { balance })
    //     } else {
    //         let user_state = smart_table::borrow_mut(&mut user_state_map.value, key);
    //         user_state.balance = balance;
    //     }
    // }

    // public fun get_token_data(owner: address, token_metadata_address: address): TokenData acquires TokenMap {
    //     let token_map = borrow_global<TokenMap>(owner);
    //     assert!(smart_table::contains(&token_map.value, token_metadata_address), E_TOKEN_NOT_EXISTS);

    //     *smart_table::borrow(&token_map.value, token_metadata_address)
    // }
    // fun set_total_supply(owner: address, token_metadata_address: address, total_supply: u128) acquires TokenMap {
    //     let token_map = borrow_global_mut<TokenMap>(owner);
    //     let token_data =
    //         smart_table::borrow_mut(&mut token_map.value, token_metadata_address);
    //     token_data.total_supply = total_supply;
    // }
    
    // public fun get_underlying_asset(token_data: &TokenData): address {
    //     token_data.underlying_asset
    // }

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
        let account_address = signer::address_of(signer);
        let token_metadata_address =
            object::create_object_address(&account_address, *string::bytes(&symbol));
        // let token_map = borrow_global_mut<TokenMap>(account_address);
        // assert!(!smart_table::contains(&token_map.value, token_metadata_address),
            // E_TOKEN_ALREADY_EXISTS);
        // let token_data = TokenData { underlying_asset,type_of_token, total_supply: 0 };
        // smart_table::add(&mut token_map.value, token_metadata_address, token_data);

        let constructor_ref = &object::create_named_object(signer, *string::bytes(&symbol));
        primary_fungible_store::create_primary_store_enabled_fungible_asset(constructor_ref,
            option::none(),
            name,
            symbol,
            decimals,
            icon_uri,
            project_uri, );

        // Create mint/burn/transfer refs to allow creator to manage the fungible asset.
        let mint_ref = fungible_asset::generate_mint_ref(constructor_ref);
        let burn_ref = fungible_asset::generate_burn_ref(constructor_ref);
        let transfer_ref = fungible_asset::generate_transfer_ref(constructor_ref);
        let metadata_object_signer = object::generate_signer(constructor_ref);
        move_to(&metadata_object_signer, ManagedFungibleAsset {
            mint_ref,
            transfer_ref,
            burn_ref
        });
        return token_metadata_address
    }

    public(friend) fun mint(
        caller: address,
        to: address,
        amount: u128,
        metadata_address: address,
    ) acquires ManagedFungibleAsset {
        // assert_token_exists(caller ,metadata_address);

        // let user_state = get_user_state(caller, to, metadata_address);
        // let new_balance = user_state.balance + amount;
        // set_user_state(caller, to, metadata_address, new_balance);

        // update scale total supply
        // let token_data = get_token_data(caller, metadata_address);
        // let total_supply = token_data.total_supply + amount;
        // set_total_supply(caller, metadata_address, total_supply);

        // fungible asset mint
        let asset = get_metadata(metadata_address);
        let managed_fungible_asset = authorized_borrow_refs(asset);
        let to_wallet =
            primary_fungible_store::ensure_primary_store_exists(to, asset);
        // freeze account
        fungible_asset::set_frozen_flag(&managed_fungible_asset.transfer_ref, to_wallet, true);

        let fa = fungible_asset::mint(&managed_fungible_asset.mint_ref, (amount as u64));
        fungible_asset::deposit_with_ref(&managed_fungible_asset.transfer_ref, to_wallet, fa);

        // event::emit(Transfer { from: @0x0, to: on_behalf_of, value: amount_to_mint, });
        // event::emit(Mint { caller, on_behalf_of, value: amount_to_mint, balance_increase, index, });
    }

    // fun assert_token_exists(caller: address, token_metadata_address: address) acquires TokenMap {
    //     let a_token_map = borrow_global<TokenMap>(caller);
    //     assert!(smart_table::contains(&a_token_map.value, token_metadata_address),
    //         E_TOKEN_ALREADY_EXISTS);
    // }

    public(friend) fun burn(
        caller: address,
        to: address,
        amount: u128,
        metadata_address: address,
    ) acquires ManagedFungibleAsset {
        // assert_token_exists(caller, metadata_address);

        // let user_state = get_user_state(caller, to, metadata_address);
        // let new_balance = user_state.balance - amount;
        // set_user_state(caller, to, metadata_address, new_balance);

        // // update total supply
        // let token_data = get_token_data(caller, metadata_address);
        // let total_supply = token_data.total_supply  - amount;
        // set_total_supply(caller, metadata_address, total_supply);

        // burn fungible asset
        let asset = get_metadata(metadata_address);
        let burn_ref = &authorized_borrow_refs(asset).burn_ref;
        let from_wallet = primary_fungible_store::primary_store(to, asset);
        fungible_asset::burn_from(burn_ref, from_wallet, (amount as u64));

    }

    // public fun balance_of(owner: address, metadata_address: address): u256 acquires UserStateMap {
    //     let user_state_map = get_user_state(owner, metadata_address);
    //     (user_state_map.balance as u256)
    // }

    public fun balance_of(owner: address, metadata_address: address): u256 {
        let metadata = get_metadata(metadata_address);
        (primary_fungible_store::balance(owner, metadata) as u256)
    }

    // public fun total_supply(owner: address, metadata_address: address): u256 acquires TokenMap {
    //     let token_data = get_token_data(owner, metadata_address);
    //     (token_data.total_supply as u256)
    // }

    public fun supply(metadata_address: address): Option<u128> {
        let asset = get_metadata(metadata_address);
        fungible_asset::supply(asset)
    }

    public fun get_user_balance_and_supply(owner: address, metadata_address: address): (u256, Option<u128>) {
        (balance_of(owner, metadata_address), supply(metadata_address))
    }

    public fun maximum(metadata_address: address): Option<u128> {
        let asset = get_metadata(metadata_address);
        fungible_asset::maximum(asset)
    }

    public fun name(metadata_address: address): String {
        let asset = get_metadata(metadata_address);
        fungible_asset::name(asset)
    }

    public fun symbol(metadata_address: address): String {
        let asset = get_metadata(metadata_address);
        fungible_asset::symbol(asset)
    }

    public fun decimals(metadata_address: address): u8 {
        let asset = get_metadata(metadata_address);
        fungible_asset::decimals(asset)
    }

    inline fun get_metadata(metadata_address: address): Object<Metadata> {
        object::address_to_object<Metadata>(metadata_address)
    }

    inline fun authorized_borrow_refs(
        asset: Object<Metadata>,
    ): &ManagedFungibleAsset acquires ManagedFungibleAsset {
        borrow_global<ManagedFungibleAsset>(object::object_address(&asset))
    }

    // #[test_only]
    // public fun test_init_module(signer: &signer) {
    //     init_module(signer);
    // }
}
