module nippy_pool::pool_factory {
    use std::signer;
    use std::string::{Self, String};
    use std::vector;
    use std::bcs;

    use aptos_framework::account::{Self,SignerCapability};
    use aptos_framework::event::Self;
    use aptos_framework::fungible_asset::Metadata;
    use aptos_framework::object::{Self, Object};
    use aptos_framework::resource_account;
    use aptos_std::smart_table::{Self, SmartTable};
    use nippy_pool::token_base;
    use nippy_pool::underlying_token_factory::Self;

    use nippy_pool::pool::{Self, LoanAssetInfo, Storage};

    struct User has key, store, copy, drop {
        pools: vector<address>,
    }
    struct State has key {
        users: SmartTable<address, User>,
        pool_owners: SmartTable<address, address>,
        pool_caps: SmartTable<address, SignerCapability>,
        nonces: u64
    }
    #[event]
    struct PoolCreated has store, drop {
        owner: address,
        pool: address,
        underlying_currency: address,
        min_first_loss_cushion: u32,
        validator_required: bool,
        debt_ceiling: u256,
    }
    #[event]
    struct TokenBought has store, drop {
        pool: address,
        sender: address,
        type_of_token: u8,
        currency_amount: u256,
        token_amount: u256,
    }
    #[event]
    struct SotTGESet has store, drop {
        pool: address, 
        interest_rate: u32, 
        opening_time: u64, 
        total_cap: u256, 
        min_bid_amount: u256
    }
    #[event]
    struct JotTGESet has store, drop {
        pool: address, 
        opening_time: u64, 
        total_cap: u256, 
        min_bid_amount: u256, 
        initial_amount: u256
    }
    #[event]
    struct DebtOrderFilled has store, drop {
        pool: address,
        from: address,
        amount: u256,
    }
    #[event]
    struct RiskScoreSet has store, drop {
        owner: address,
        pool: address,
    }
    fun init_module(signer: &signer) {
        move_to(signer, State { 
            users: smart_table::new<address, User>(),
            pool_owners: smart_table::new<address, address>(),
            pool_caps: smart_table::new<address, SignerCapability>(),
            nonces: 0u64
        });
    }
    fun user_default(): User {
        return User {
            pools: vector::empty<address>(),
        }
    }
    public entry fun create_pool(owner: &signer, currency: address, min_first_loss_cushion: u32, validator_required: bool, debt_ceiling: u256) acquires State{
        let state = borrow_global_mut<State>(@nippy_pool);
        let user = smart_table::borrow_mut_with_default(&mut state.users, signer::address_of(owner), user_default());
        let seed = bcs::to_bytes<u64>(&state.nonces);
        let (pool_account, pool_cap) = account::create_resource_account(owner, seed);
        let pool = signer::address_of(&pool_account);

        pool::init_pool(&pool_account, currency, min_first_loss_cushion, validator_required, debt_ceiling);

        // update state
        state.nonces = state.nonces + 1;
        vector::push_back(&mut user.pools, pool);
        smart_table::add(&mut state.pool_owners, pool, signer::address_of(owner));
        smart_table::add(&mut state.pool_caps, pool, pool_cap);
        event::emit(
            PoolCreated{
                owner: signer:: address_of(owner),
                pool: pool,
                underlying_currency: currency ,
                min_first_loss_cushion: min_first_loss_cushion,
                validator_required: validator_required,
                debt_ceiling: debt_ceiling,
        });
    }
    public entry fun set_up_risk_scores(sender: &signer ,pool: address, days_past_dues: vector<u32>, rates_and_defaults: vector<u32>, periods_and_write_offs: vector<u32>) acquires State{
        let state = borrow_global_mut<State>(@nippy_pool);
        assert!(
            signer::address_of(sender) == *smart_table::borrow_with_default(&state.pool_owners, pool, &@0x0),
            40
        );
        pool::set_up_risk_scores(pool, days_past_dues, rates_and_defaults, periods_and_write_offs);
        event::emit(RiskScoreSet{
            owner: signer::address_of(sender),
            pool: pool
        });
    }
    public entry fun fill_debt_order(
        pool: address,
        sender: address,
        asset_purpose: u8,
        principal_token_address: address,
        debtors: vector<address>,
        // principal_amount: vector<u256>,
        expiration_timestamps: vector<u256>,
        salts: vector<u256>,
        risk_scores: vector<u8>,
        terms_params: vector<u256>, 
        lat_infos: vector<vector<u256>>
    ){
        let amount = pool::fill_debt_order(pool, sender, asset_purpose, principal_token_address, debtors, expiration_timestamps, salts, risk_scores, terms_params, lat_infos);
        event::emit(DebtOrderFilled{
            pool: pool,
            from: sender,
            amount: amount
        });
    }
    public entry fun set_up_tge_for_sot(sender: &signer, pool: address, interest_rate: u32, opening_time: u64, total_cap: u256, min_bid_amount: u256) acquires State{
        let state = borrow_global_mut<State>(@nippy_pool);
        assert!(
            signer::address_of(sender) == *smart_table::borrow_with_default(&state.pool_owners, pool, &@0x0),
            40
        );
        let signer_cap = smart_table::borrow(&state.pool_caps, pool);
        let pool_signer = account::create_signer_with_capability(signer_cap);
        pool::set_up_tge_for_sot(&pool_signer, interest_rate, opening_time, total_cap, min_bid_amount);
        event::emit({
            SotTGESet{
                pool: pool, 
                interest_rate, 
                opening_time, 
                total_cap, 
                min_bid_amount
            }
        });
    }
    public entry fun set_up_tge_for_jot(sender: &signer, pool: address, opening_time: u64, total_cap: u256, min_bid_amount: u256, initial_amount: u256) acquires State{
        let state = borrow_global_mut<State>(@nippy_pool);
        assert!(
            signer::address_of(sender) == *smart_table::borrow_with_default(&state.pool_owners, pool, &@0x0),
            40
        );
        let signer_cap = smart_table::borrow(&state.pool_caps, pool);
        let pool_signer = account::create_signer_with_capability(signer_cap);
        pool::set_up_tge_for_jot(&pool_signer, opening_time, total_cap, min_bid_amount, initial_amount);
        event::emit({
            JotTGESet{
                pool: pool, 
                opening_time, 
                total_cap, 
                min_bid_amount,
                initial_amount, 
            }
        });
    }
    public entry fun buy_token(sender: &signer, pool: address, beneficiary: address, type_of_token: u8, currency_amount: u256) {
        let token_amount = pool::buy_token(sender, pool, beneficiary, type_of_token, currency_amount);
        event::emit(
            TokenBought{
                pool: pool,
                sender: signer::address_of(sender),
                type_of_token: type_of_token,
                currency_amount: currency_amount,
                token_amount: token_amount
        });
    }

    #[test_only]
    public fun test_init_module(signer: &signer) {
        init_module(signer);
    }
    #[view]
    public fun get_current_nav(pool: address): u256 {
        return pool::get_current_nav(pool)
    }
    #[view]
    public fun get_current_navs(pools: vector<address>): vector<u256> {
        let navs = vector::empty<u256>();
        let i = 0u64;
        let length = vector::length(&pools);
        while(i < length) {
            vector::push_back(&mut navs, get_current_nav(*vector::borrow(&pools,i)));
            i = i + 1;
        };
        return navs
    }
    #[view]
    public fun get_total_current_navs(pools: vector<address>): u256 {
        let total_nav = 0u256;
        let i = 0u64;
        let length = vector::length(&pools);
        while(i < length) {
            total_nav = total_nav + get_current_nav(*vector::borrow(&pools,i));
            i = i + 1;
        };
        return total_nav
    }
    #[view]
    public fun get_capital_reserve(pool: address): u256 {
        return pool::get_capital_reserve(pool)
    }
    #[view]
    public fun get_interest_rate_sot(pool: address): u32 {
        return pool::get_interest_rate_sot(pool)
    }
    #[view]
    public fun get_token_price(pool: address): (u256,u256) {
        return pool::get_token_price(pool)
    }
    #[view]
    public fun get_sot_capacity(pool: address): u256 {
        return pool::get_sot_capacity(pool)
    }
    #[view]
    public fun get_jot_capacity(pool: address): u256 {
        return pool::get_jot_capacity(pool)
    }
    #[view]
    public fun get_total_sot(pool: address): u256 {
        return pool::get_total_sot(pool)
    }
    #[view]
    public fun get_total_jot(pool: address): u256 {
        return pool::get_total_jot(pool)
    }
}
