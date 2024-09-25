module nippy_pool::pool_tests {
    use std::option;
    use std::option::Option;
    use std::signer::Self;
    use std::string::{utf8, String};
    use std::vector;
    use std::bcs;

    use std::debug::print; 

    use aptos_framework::timestamp;
    use aptos_framework::event;
    use aptos_framework::account;

    use nippy_pool::pool::{Self, LoanAssetInfo};
    use nippy_pool::underlying_token_factory::{Self};
    use nippy_pool::token_base::{Self};
    use nippy_pool::pool_factory::{Self, PoolCreated};

    const ETHER: u256 = 1000000000000000000;
    #[test(aptos_framework = @0x1 ,signer =  @nippy_pool ,alice = @0x69a, bob = @0x69b, investor = @0xdca, borrower = @0xacd)]
    public fun test_init_pool(signer: &signer, alice: &signer, bob: &signer, investor: &signer, borrower: &signer, aptos_framework: &signer) {

        timestamp::set_time_has_started_for_testing(aptos_framework);
        timestamp::update_global_time_for_test_secs(1725973642u64);

        // init underlying currency factory
        underlying_token_factory::test_init_module(signer);
        underlying_token_factory::create_token(
            signer,
            0u128,
            utf8(b"USD-peg Token"),
            utf8(b"USDC"),
            6u8,
            utf8(b"http://example.com/favicon.ico"),
            utf8(b"http://example.com")
        );


        let usdc = underlying_token_factory::token_address(utf8(b"USDC"));
        let min_first_loss_cushion = 10u32 * 10000u32;
        let validator_required = false;
        let debt_ceiling = 20000u256 * ETHER;
        pool_factory::test_init_module(signer);
        pool_factory::create_pool(alice, usdc, min_first_loss_cushion, validator_required, debt_ceiling);
        pool_factory::create_pool(alice, usdc, min_first_loss_cushion, validator_required, debt_ceiling);
        pool_factory::create_pool(bob, usdc, min_first_loss_cushion, validator_required, debt_ceiling);
        // let events = event::emitted_events<PoolCreated>();
        // print(&events);
        let pool1_address = account::create_resource_address(&signer::address_of(alice),bcs::to_bytes<u64>(&0));
        let pool2_address = account::create_resource_address(&signer::address_of(alice),bcs::to_bytes<u64>(&1));
        let pool3_address = account::create_resource_address(&signer::address_of(bob),bcs::to_bytes<u64>(&2));

        // NEED to check state but later
        // print(&pool::get_storage());

        let days_past_dues = vector<u32>[86400];
        let rates_and_defaults = vector<u32>[
            950000,
            900000,
            910000,
            800000,
            810000,
            100000
        ];
        let periods_and_write_offs = vector<u32>[
            43200,
            43200,
            43200,
            43200,
        ];

        pool_factory::set_up_risk_scores(alice, pool1_address ,days_past_dues,rates_and_defaults, periods_and_write_offs);
        pool_factory::set_up_risk_scores(alice, pool2_address ,days_past_dues,rates_and_defaults, periods_and_write_offs);
        pool_factory::set_up_risk_scores(bob, pool3_address ,days_past_dues,rates_and_defaults, periods_and_write_offs);

        // // create a tokens admin account
        // account::create_account_for_test(pool1_address);

        // token_base::test_init_module(alice);

        let interest_rate = 10000u32;
        let opening_time = 1725973642u64;
        let total_cap = 100000u256 * ETHER;
        let min_bid_amount = 1u256 * ETHER;
        pool_factory::set_up_tge_for_sot(alice, pool1_address, interest_rate, opening_time, total_cap, min_bid_amount);
        pool_factory::set_up_tge_for_sot(alice, pool2_address, interest_rate, opening_time, total_cap, min_bid_amount);
        pool_factory::set_up_tge_for_sot(bob, pool3_address, interest_rate, opening_time, total_cap, min_bid_amount);

        let init_jot_amount = 100u256 * ETHER;
        pool_factory::set_up_tge_for_jot(alice, pool1_address ,opening_time, total_cap, min_bid_amount, init_jot_amount);
        pool_factory::set_up_tge_for_jot(alice, pool2_address ,opening_time, total_cap, min_bid_amount, init_jot_amount);
        pool_factory::set_up_tge_for_jot(bob, pool3_address ,opening_time, total_cap, min_bid_amount, init_jot_amount);

        // // // mint to nippy pool
        underlying_token_factory::mint(signer, signer::address_of(alice), 1000000u64 * 1000000u64, usdc);

        pool_factory::buy_token(alice ,pool1_address, signer::address_of(investor), 1u8, 10000u256 * 1000000u256);        
        pool_factory::buy_token(alice ,pool2_address, signer::address_of(investor), 1u8, 10000u256 * 1000000u256);        
        pool_factory::buy_token(alice ,pool3_address, signer::address_of(investor), 1u8, 10000u256 * 1000000u256);        
        // pool_factory::buy_token(signer::address_of(alice), signer::address_of(investor), signer::address_of(investor), 0u8, 10000u256 * 1000000u256);        
        // print(&underlying_token_factory::balance_of(signer::address_of(alice), usdc));

        let asset_purpose = 0u8;
        let principal_token_address = usdc;
        let debtors =  vector<address>[
            signer::address_of(borrower),
            // signer::address_of(borrower),
        ];
        let principal_amount = vector<u256>[
            100u256 * ETHER,
            // 100u256 * ETHER
        ];

        let expiration_timestamps = vector<u256> [
            1725973642 + 7 * 86400,
            // 1725450326
        ];

        let salts =  vector<u256>[
            1u256,
            // 2u256,
        ];

        let risk_scores =  vector<u8>[
            1u8,
            // 1u8,
        ];

        let terms_params = vector<u256>[
            146150163733090291820368483271628306392811874937582256128,
            // 570916091221997647279046210476630555992583569408u256
        ]; 
        let token_ids = vector::singleton<u256>(101u256);
        let lat_infos = vector::singleton<vector<u256>>(token_ids);
        // print(&underlying_token_factory::balance_of(@nippy_pool, usdc));
        pool_factory::fill_debt_order(
            borrower,
            pool1_address,
            asset_purpose,
            principal_token_address,
            debtors,
            // principal_amount,
            expiration_timestamps,
            salts,
            risk_scores,
            terms_params, 
            lat_infos
        );
        pool_factory::fill_debt_order(
            borrower,
            pool2_address,
            asset_purpose,
            principal_token_address,
            debtors,
            // principal_amount,
            expiration_timestamps,
            salts,
            risk_scores,
            terms_params, 
            lat_infos
        );
        pool_factory::fill_debt_order(
            borrower,
            pool3_address,
            asset_purpose,
            principal_token_address,
            debtors,
            // principal_amount,
            expiration_timestamps,
            salts,
            risk_scores,
            terms_params, 
            lat_infos
        );
        // print(&underlying_token_factory::balance_of(pool1_address, usdc));
        // print(&underlying_token_factory::balance_of(signer::address_of(alice), usdc));
        // print(&underlying_token_factory::balance_of(signer::address_of(borrower), usdc));
        // let (x,y) = pool_factory::get_token_price(pool1_address);
        // print(&x);
        // print(&y);

        print(&pool_factory::get_current_nav(pool1_address));
        print(&pool_factory::get_current_nav(pool2_address));
        print(&pool_factory::get_current_nav(pool3_address));
        pool_factory::repay(
            borrower,
            pool1_address,
            token_ids,
            vector<u256>[10u256 * 1000000u256]
        );
    }

} 