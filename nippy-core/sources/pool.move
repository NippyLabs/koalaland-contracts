module nippy_pool::pool {
    use std::signer;
    use aptos_std::smart_table::{Self, SmartTable};
    use std::vector;
    use aptos_framework::timestamp;
    use std::string::{String,utf8};
    use aptos_std::string_utils::format2;
    use aptos_framework::event;

    use nippy_math::math;
    use nippy_math::discounting;
    use nippy_pool::rebase_logic::{Self};
    use nippy_pool::generic_logic::{Self};
    use nippy_pool::loan_kernel_logic::{Self};
    use nippy_pool::token_factory::{Self};
    use nippy_pool::underlying_token_factory::{Self};
    use nippy_pool::minted_normal_tge::{Self};

    // friend nippy_pool::pool_tests;
    friend nippy_pool::pool_factory;

    const RATE_SCALING_FACTOR: u256 = 10_000;
    const ONE_HUNDRED_PERCENT: u256 = 1_000_000;

    const ONE: u256 = 1_000_000_000_000_000_000_000_000_000;
    const WRITE_OFF_RATE_GROUP_START: u256 = 1_000_000_000_000_000_000_000_000_000_000;
    const PRICE_DECIMAL: u256 = 1_000_000_000_000_000_000;
    
    public fun rate_scaling_factor(): u256 {
        RATE_SCALING_FACTOR
    }

    public fun one_hundred_percent(): u256 {
        ONE_HUNDRED_PERCENT
    }

    public fun one(): u256 {
        ONE
    }

    public fun write_off_rate_group_start(): u256 {
        WRITE_OFF_RATE_GROUP_START
    }

    public fun price_decimal(): u256 {
        PRICE_DECIMAL
    }

    #[event]
    struct AssetRepaid has store, drop {
        pool: address,
        originator: address,
        token_id: u256,
        underlying_currency: address,
        repay_amount: u256,
        outstanding_amount: u256,
    }
    struct RiskScore has key, store, copy, drop {
        days_past_due: u32,
        advance_rate: u32,
        penalty_rate: u32,
        interest_rate: u32,
        probability_of_default: u32,
        loss_given_default: u32,
        write_off_after_grace_period: u32,
        grace_period: u32,
        collection_period: u32,
        write_off_after_collection_period: u32,
        discount_rate: u32
    }

    struct LoanEntry has key, store, copy, drop{
        debtor: address,
        principal_token_address: address,
        terms_param: u256, // actually inside this param was already included P token address
        salt: u256,
        issuance_block_timestamp: u256,
        expiration_timestamp: u256,
        risk_score: u8,
        /*
            asset_purpose = 0 --> LOAN
            asset_purpose = 1 --> INVOICE
        */
        asset_purpose: u8 
    }

    struct InterestParams has drop{
        principal_amount: u256,
        term_start_unix_timestamp: u256,
        term_end_unix_timestamp: u256,
        /*
            amortization_unit_type = 0 --> MINUTES
            amortization_unit_type = 1 --> HOURS
            amortization_unit_type = 2 --> DAYS
            amortization_unit_type = 3 --> WEEKS
            amortization_unit_type = 4 --> MONTHS
            amortization_unit_type = 5 --> YEARS
        */
        amortization_unit_type: u8,
        term_length_in_amortization_units: u256,
        // interest rates can, at a maximum, have 4 decimal places of precision.
        interest_rate: u256
    }

    struct NFTAsset has key, store, copy, drop{
        token_address: address,
        token_id: u256
    }
    struct NewPoolParams has key, store, copy, drop{
        currency: address,
        min_first_loss_cushion: u32,
        validator_required: bool,
        debt_ceiling: u256
    }
    
    struct NFTDetails has key, store, copy, drop{
        future_value: u128,
        maturity_date: u128,
        risk: u64,
        debtor: address,
        principal_token_address: address,
        salt: u256,
        issuance_block_timestamp: u256,
        expiration_timestamp: u256,
        /*
            asset_purpose = 0 --> LOAN
            asset_purpose = 1 --> INVOICE
        */
        asset_purpose: u8,
        terms_param: u256,
        principal_amount: u256,
        term_start_unix_timestamp: u256,
        term_end_unix_timestamp: u256,
        /*
            amortization_unit_type = 0 --> MINUTES
            amortization_unit_type = 1 --> HOURS
            amortization_unit_type = 2 --> DAYS
            amortization_unit_type = 3 --> WEEKS
            amortization_unit_type = 4 --> MONTHS
            amortization_unit_type = 5 --> YEARS
        */
        amortization_unit_type: u8,
        term_length_in_amortization_units: u256,
        interest_rate: u256,
    }

    struct Rate has key, store, copy, drop{
        // total debt of all loans with this rate
        pie: u256,
        // accumlated rate index over time
        chi: u256,
        // interest rate per second
        rate_per_second: u256,
        // penalty rate per second
        penalty_rate_per_second: u256,
        // accumlated penalty rate index over time
        penalty_chi: u256,
        // last time the rate was accumulated
        last_updated: u64,
        // time start to penalty
        time_start_penalty: u32
    }

    struct LoanDetails has key, store, copy, drop{
        borrowed: u128,
        // only auth calls can move loan into different writeOff group
        auth_write_off: bool
    }

    struct WriteOffGroup has key, store, copy, drop {
        // denominated in (10^27)
        percentage: u128,
        // amount of days after the maturity days that the writeoff group can be applied by default
        overdue_days: u128,
        risk_index: u64
    }

    struct LoanAssetInfo has copy, drop {
        token_ids: vector<u256>,
        nonces: vector<u256>,
        validator: address,
        validate_signature: vector<u8>
    }

    struct Storage has key, store, copy, drop {
        validator_required: bool,
        first_asset_timestamp: u64,
        risk_scores: vector<RiskScore>,
        nft_assets: vector<NFTAsset>,
        // tge_address: address,
        // second_tge_address: address,
        sot_token: address,
        jot_token: address,
        underlying_currency: address,
        income_reserve: u256,
        capital_reserve: u256,
        min_first_loss_cushion: u32,
        opening_block_timestamp: u64,
        // by default it is address(this)
        // pot: address,
        interest_rate_sot: u32,
        total_asset_repaid_currency: u256,
        debt_ceiling: u256,
        
        // mapping(uint256 => Rate) rates;
        // rates: SmartTable<u256, Rate>,

        // mapping(uint256 => uint256) pie;
        // pie: SmartTable<u256, u256>,

        /// @notice mapping from loan => rate
        // mapping(uint256 => uint256) loanRates;
        // loan_rates: SmartTable<u256,u256>,

        /// @notice mapping from loan => grace time
        loan_count: u256,

        // mapping(uint256 => uint256) balances;
        // balances: SmartTable<u256,u256>,

        balance: u256,
        // nft => details
        // mapping(bytes32 => NFTDetails) details;
        // details: SmartTable<u256, NFTDetails>,

        // loan => details
        // mapping(uint256 => LoanDetails) loanDetails;
        // loan_details: SmartTable<u256, LoanDetails>,

        // timestamp => bucket
        // mapping(uint256 => uint256) buckets;
        // buckets: SmartTable<u256,u256>,

        // WriteOffGroup[] writeOffGroups;
        write_off_groups: vector<WriteOffGroup>,
        // Write-off groups will be added as rate groups to the pile with their index
        // in the writeOffGroups array + this number
        //        uint256 constant WRITEOFF_RATE_GROUP_START = 1000 * ONE;
        //        uint256 constant INTEREST_RATE_SCALING_FACTOR_PERCENT = 10 ** 4;

        // Discount rate applied on every asset's fv depending on its maturityDate.
        // The discount decreases with the maturityDate approaching.
        // denominated in (10^27)
        discount_rate: u256,
        // latestNAV is calculated in case of borrows & repayments between epoch executions.
        // It decreases/increases the NAV by the repaid/borrowed amount without running the NAV calculation routine.
        // This is required for more accurate Senior & JuniorAssetValue estimations between epochs
        latest_nav: u256,
        latest_discount: u256,
        last_nav_update: u256,
        // overdue loans are loans which passed the maturity date but are not written-off
        overdue_loans: u256,
        // tokenId => latestDiscount
        // mapping(bytes32 => uint256) latestDiscountOfNavAssets;
        // latest_discount_of_nav_assets: SmartTable<u256, u256>,

        // mapping(bytes32 => uint256) overdueLoansOfNavAssets;
        // overdue_loans_of_nav_assets: SmartTable<u256,u256>,

        // mapping(uint256 => bytes32) loanToNFT;
        // loan_to_nft: SmartTable<u256,u256>,

        // value to view
        total_principal_repaid: u256,
        total_interest_repaid: u256,
        // value to calculate rebase
        senior_debt: u256,
        senior_balance: u256,
        last_update_senior_interest: u64,
    }

    struct TimeGeneratedEvent has key, store, copy, drop{
        token: address,
        has_started: bool,
        
        /// @dev Timestamp at which the first asset is collected to pool
        first_note_token_minted_timestamp: u64,

        /// @dev Amount of currency raised
        currency_raised: u256,

        /// @dev Amount of token raised
        token_raised: u256,

        /// @dev Target raised currency amount
        total_cap: u256,

        /// @dev Minimum currency bid amount for note token
        min_bid_amount: u256,

        initial_amount: u256,

        opening_time: u64
    }
    // 0 --> TGE SOT
    // 1 --> TGE JOT
    struct TimeGeneratedEventList has key {
        value: SmartTable<u8, TimeGeneratedEvent>,
        count: u8
    }

    struct Mapping has key {
        rates: SmartTable<u256, Rate>,
        pie: SmartTable<u256, u256>,
        loan_rates: SmartTable<u256,u256>,
        balances: SmartTable<u256,u256>,
        details: SmartTable<u256, NFTDetails>,
        loan_details: SmartTable<u256, LoanDetails>,
        buckets: SmartTable<u256,u256>,
        latest_discount_of_nav_assets: SmartTable<u256, u256>,
        overdue_loans_of_nav_assets: SmartTable<u256,u256>,
        loan_to_nft: SmartTable<u256,u256>,
        underlying_currency_raised_by_investor_sot: SmartTable<address, u256>,
        underlying_currency_raised_by_investor_jot: SmartTable<address, u256>,
    }


    public(friend) fun init_pool(account: &signer, currency: address, min_first_loss_cushion: u32, validator_required: bool, debt_ceiling: u256){
        let storage = storage_default();
        storage.underlying_currency =  currency;
        
        assert!((min_first_loss_cushion as u256) <= 100 * RATE_SCALING_FACTOR, 24);
        storage.min_first_loss_cushion =  min_first_loss_cushion;

        storage.validator_required =  validator_required;
        storage.debt_ceiling =  debt_ceiling;
        move_to(
            account,
            storage
        );
        move_to(
            account,
            mapping_default()
        );
        move_to(
            account,
            time_generate_event_list_default()
        );
    }

    
    public fun get_risk_score_by_idx(risk_scores: vector<RiskScore>, idx: u64): RiskScore {
        let risk_score = RiskScore {
            days_past_due: 0,
            advance_rate: 1000000,
            penalty_rate: 0,
            interest_rate: 0,
            probability_of_default: 0,
            loss_given_default: 0,
            write_off_after_grace_period: 0,
            grace_period: 0,
            collection_period: 0,
            write_off_after_collection_period: 0,
            discount_rate: 0
        };
        
        if (idx == 0 || vector::length(&risk_scores) == 0){
            return risk_score
        };
        return *vector::borrow(&risk_scores,idx -1)
    }

    public (friend) fun set_up_risk_scores(
        pool: address,
        days_past_dues: vector<u32>,
        rates_and_defaults: vector<u32>,
        periods_and_write_offs: vector<u32>
    ) acquires Storage, Mapping{
        // Need check pause and admin role later
        let storage = borrow_global_mut<Storage>(pool);
        let mapping = borrow_global_mut<Mapping>(pool);

        let days_past_dues_length = vector::length(&days_past_dues);
        let rates_and_defaults_length = vector::length(&rates_and_defaults);
        let periods_and_write_offs_length = vector::length(&periods_and_write_offs);
        assert!(
            days_past_dues_length * 6 == rates_and_defaults_length && 
            days_past_dues_length * 4 == periods_and_write_offs_length,
            3
        );
    
        let risk_scores = vector::empty<RiskScore>();
        let i = 0u64;
        loop
        {
            assert!(i == 0 || *vector::borrow(&days_past_dues,i) > *vector::borrow(&days_past_dues,i - 1), 4);
            let interest_rate = *vector::borrow(&rates_and_defaults,i + days_past_dues_length * 2);
            let write_off_after_grace_period = *vector::borrow(&periods_and_write_offs, i + days_past_dues_length * 2);
            let write_off_after_collection_period = *vector::borrow(&periods_and_write_offs, i + days_past_dues_length * 3);
            vector::push_back(
                &mut risk_scores,
                RiskScore{
                    days_past_due: *vector::borrow(&days_past_dues,i),
                    advance_rate: *vector::borrow(&rates_and_defaults,i),
                    penalty_rate: *vector::borrow(&rates_and_defaults,i + days_past_dues_length),
                    interest_rate: interest_rate,
                    probability_of_default: *vector::borrow(&rates_and_defaults,i + days_past_dues_length * 3),
                    loss_given_default: *vector::borrow(&rates_and_defaults,i + days_past_dues_length * 4),
                    discount_rate: *vector::borrow(&rates_and_defaults,i + days_past_dues_length * 5),
                    grace_period: *vector::borrow(&periods_and_write_offs,i),
                    collection_period: *vector::borrow(&periods_and_write_offs,i + days_past_dues_length),
                    write_off_after_grace_period: write_off_after_grace_period,
                    write_off_after_collection_period: *vector::borrow(&periods_and_write_offs,i + days_past_dues_length * 3)
                }
            );

            file(
                storage,
                mapping, 
                1u8, 
                (interest_rate as u256), 
                (write_off_after_grace_period as u256),
                (*vector::borrow(&periods_and_write_offs,i) as u256),
                (*vector::borrow(&rates_and_defaults,i + days_past_dues_length) as u256),
                i
            );
            file(
                storage,
                mapping,
                1u8,
                (interest_rate as u256),
                (write_off_after_collection_period as u256),
                (*vector::borrow(&periods_and_write_offs,i + days_past_dues_length) as u256),
                (*vector::borrow(&rates_and_defaults,i + days_past_dues_length) as u256),
                i
            );

            i = i + 1;
            if(i >= days_past_dues_length)
                break;
        };

        file_discount_rate(storage, (vector::borrow<RiskScore>(&risk_scores,0).discount_rate as u256));
        storage.risk_scores = risk_scores; // update risk_score

        // rebase
        rebase(storage, mapping);
    }

    public fun export_assets(
        pool: address,
        token_address: address,
        to_pool_address: address,
        token_ids: vector<u256> 
    ) acquires Storage{
        // need to check pause and permission admin/owner later
        let token_ids_length = vector::length(&token_ids);

        let nft_assets = borrow_global_mut<Storage>(pool).nft_assets;
        let i = 0u64;
        loop
        {
            let (is_exist, index) = vector::index_of<NFTAsset>(
                &nft_assets,
                &NFTAsset{
                    token_address: token_address,
                    token_id: *vector::borrow(&token_ids,i)
                }
            );
            assert!(is_exist, 4);
            vector::swap_remove<NFTAsset>(&mut nft_assets,index);

            i = i+1;
            if (i >= token_ids_length)
                break;
        };

        i = 0u64;
        loop
        {
            // TODO: transfer NFT
            // UntangledERC721(tokenAddress).safeTransferFrom(address(this), toPoolAddress, tokenIds[i]);

            i = i+1;
            if (i >= token_ids_length)
                break;
        };
    }

    public fun withdraw_assets(
        pool: address, 
        token_addresses: vector<address>,
        token_ids: vector<u256>,
        recipients: vector<address>
    )acquires Storage{
        // Need to check pause and role owner later
        let token_ids_length = vector::length(&token_ids);
        let token_addresses_length = vector::length(&token_addresses);
        let recipients_length = vector::length(&recipients);
        assert!(token_ids_length == token_addresses_length, 5);
        assert!(token_ids_length == recipients_length, 5);

        let nft_assets = borrow_global_mut<Storage>(pool).nft_assets;
        let i = 0u64;
        loop
        {
            let (is_exist, index) = vector::index_of<NFTAsset>(
                &nft_assets,
                &NFTAsset{
                    token_address: *vector::borrow(&token_addresses,i),
                    token_id: *vector::borrow(&token_ids,i)
                }
            );
            assert!(is_exist, 4);
            vector::swap_remove<NFTAsset>(&mut nft_assets,index);

            i = i+1;
            if (i >= token_ids_length)
                break;
        };
        
        i = 0u64;
        loop
        {
            // TODO: transfer NFT
            // UntangledERC721(tokenAddresses[i]).safeTransferFrom(address(this), recipients[i], tokenIds[i]);

            i = i+1;
            if (i >= token_ids_length)
                break;
        };
    }

    public fun get_loans_value(
        pool: address, 
        token_ids: vector<u256>,
        loan_entries: vector<LoanEntry>
    ) :(u256, vector<u256>) acquires Storage{
        let token_ids_length = vector::length(&token_ids);
        let expected_asset_values: vector<u256> = vector::empty();
        let expected_asset_value = 0u256;

        let i = 0u64;
        loop
        {
            let asset_value = get_expected_loan_value(pool,*vector::borrow<LoanEntry>(&loan_entries,i));
            expected_asset_value = expected_asset_value + asset_value;
            vector::push_back(&mut expected_asset_values,asset_value);

            i = i+1;
            if (i >= token_ids_length)
                break;
        };
        (expected_asset_value,expected_asset_values)

        // return PoolAssetLogic.getLoansValue(_poolStorage, tokenIds, loanEntries);
    }
    fun rebase(storage: &mut Storage, mapping: &Mapping){
        let nav = current_nav(storage, mapping);
        let reserve = reserve(storage);
        let (senior_debt, senior_balance) = rebase_logic::rebase(
            nav, 
            reserve, 
            rebase_logic::calc_senior_asset(
                storage.senior_balance,
                drip_senior_debt(storage)
            )
        );
        storage.senior_debt = senior_debt;
        storage.senior_balance = senior_balance;
    }
    fun drip_senior_debt(storage: &mut Storage): u256{
        storage.senior_debt = senior_debt(storage);
        storage.last_update_senior_interest = timestamp::now_seconds();
        return storage.senior_debt
    }
    fun senior_debt(storage: &Storage): u256 {
        let last_update_senior_interest = storage.last_update_senior_interest;
        if (timestamp::now_seconds() < last_update_senior_interest)
            return storage.senior_debt;
        let converted_interest_rate = ONE + ((storage.interest_rate_sot as u256) * ONE) / (ONE_HUNDRED_PERCENT * 31536000);
        return charge_interest(storage.senior_debt, converted_interest_rate, (last_update_senior_interest as u256))
    }
    fun reserve(storage: &Storage): u256 {
        return (storage.capital_reserve + storage.income_reserve)
    }
    fun current_nav(storage: &Storage, mapping: &Mapping): u256{
        let (total_discount, overdue, write_offs): (u256,u256,u256) = current_pvs(storage, mapping);
        return (total_discount + overdue + write_offs)
    } 
    fun file_discount_rate(storage: &mut Storage, value: u256) {
        storage.discount_rate = ONE  + (value * ONE)/ (ONE_HUNDRED_PERCENT * 31536000);
    }
    // name = 1 --> name = 'writeOffGroup'
    fun file(storage: &mut Storage, mapping: &mut Mapping, name: u8, rate: u256, write_off_percentage: u256, overdue_days: u256, penalty_rate: u256, risk_index: u64) {
        if (name != 1) 
            abort 16;
        let index = (vector::length(&storage.write_off_groups) as u256);
        let converted_interest_rate = ONE + (rate * ONE) / (ONE_HUNDRED_PERCENT * 31536000);  
        let converted_write_off_percentage = ONE - (write_off_percentage * ONE) / ONE_HUNDRED_PERCENT ;  
        let converted_penalty_rate = ONE + (penalty_rate * rate * ONE) / (ONE_HUNDRED_PERCENT * ONE_HUNDRED_PERCENT * 31536000);
        let converted_overdue_days = overdue_days / 86400;
        vector::push_back<WriteOffGroup>(&mut storage.write_off_groups, WriteOffGroup {
            percentage: (converted_write_off_percentage as u128),
            overdue_days: (converted_overdue_days as u128),
            risk_index: risk_index 
        });
        file_rate(mapping, 1, WRITE_OFF_RATE_GROUP_START + index, converted_interest_rate);
        file_rate(mapping, 2, WRITE_OFF_RATE_GROUP_START + index, converted_penalty_rate);

    }
    // what = 1 --> what = 'rate'
    // what = 2 --> what = 'penalty'
    fun file_rate(mapping: &mut Mapping, what: u8, loan_rate: u256, value: u256){
        assert!(value != 0, 14);
        let rate = smart_table::borrow_mut_with_default<u256,Rate>(
            &mut mapping.rates, 
            loan_rate,
            rate_default()
        );
        if (what == 1 && rate.chi == 0) {
            rate.chi = ONE;
            rate.last_updated = timestamp::now_seconds();
            rate.rate_per_second = value;
            return
        };
        if (what == 1) {
            drip(rate);
            rate.rate_per_second = value;
            return
        };
        if (what == 2 && rate.penalty_chi == 0){
            rate.penalty_chi = ONE;
            rate.last_updated = timestamp::now_seconds();
            rate.penalty_rate_per_second = value;
            return
        };
        if (what == 2) {
            drip(rate);
            rate.penalty_rate_per_second = value;
            return
        };
        abort 15
    }
    
    public fun unpack_params_for_agreement_id(loan: LoanEntry): InterestParams {
        let principal_amount: u256;
        // The interest rate accrued per amortization unit.
        let interest_rate: u256;
        // The amortization unit in which the repayments installments schedule is defined.
        let raw_amortization_unit_type: u256;
        // The debt's entire term's length, denominated in the aforementioned amortization units
        let term_length_in_amortization_units: u256;
        // let grace_period_in_days: u256;

        (
            principal_amount, 
            _, // Ignore the initial term_length_in_amortization_units assignment
            interest_rate, 
            raw_amortization_unit_type, 
            _ // this slot for grace_period_in_days but never use
        ) = generic_logic::unpack_parameters_from_bytes(loan.terms_param);
        
        let amortization_unit_length_in_seconds = generic_logic::get_amortization_unit_length_in_seconds(raw_amortization_unit_type);
        term_length_in_amortization_units = (loan.expiration_timestamp - (timestamp::now_seconds() as u256)) /  amortization_unit_length_in_seconds;
        let term_length_in_seconds = term_length_in_amortization_units * amortization_unit_length_in_seconds;
        return InterestParams{
            principal_amount: principal_amount,
            interest_rate: interest_rate,
            term_start_unix_timestamp: loan.issuance_block_timestamp,
            term_end_unix_timestamp: term_length_in_seconds + loan.issuance_block_timestamp,
            amortization_unit_type: (raw_amortization_unit_type as u8),
            term_length_in_amortization_units: term_length_in_amortization_units
        }
    }

    fun get_expected_loan_value(pool: address,loan_entry: LoanEntry): u256 acquires Storage{
        let loan_param = unpack_params_for_agreement_id(loan_entry);
        let risk_param = get_risk_score_by_idx(borrow_global<Storage>(pool).risk_scores, (loan_entry.risk_score as u64));
        (loan_param.principal_amount * (risk_param.advance_rate as u256)) / ONE_HUNDRED_PERCENT
    }
    fun collect_assets(storage: &mut Storage, mapping: &mut Mapping, tge_list: &mut TimeGeneratedEventList, token_ids: vector<u256>, loan_entries: vector<LoanEntry>): u256 {
        // need check pause and only loankernel later
        let tge_sot = smart_table::borrow_with_default(&tge_list.value, 0u8, &time_generate_event_default());

        let token_ids_length = vector::length(&token_ids);
        let expected_assets_value = 0u256;
        let i = 0u64; 
        while (i < token_ids_length){
            expected_assets_value = expected_assets_value + add_loan(
                storage,
                mapping,
                *vector::borrow(&token_ids, i),
                *vector::borrow(&loan_entries, i),
            );
            i = i + 1;
        };
        if (storage.first_asset_timestamp == 0) {
            storage.first_asset_timestamp = timestamp::now_seconds();
            set_up_opening_block_timestamp(storage, tge_sot.first_note_token_minted_timestamp);
        };
        if (storage.opening_block_timestamp == 0){
            storage.opening_block_timestamp = timestamp::now_seconds();
        };
        return expected_assets_value
    }
    public (friend) fun fill_debt_order(
        sender: address,
        pool: address,
        asset_purpose: u8,
        principal_token_address: address,
        debtors: vector<address>,
        // principal_amount: vector<u256>,
        expiration_timestamps: vector<u256>,
        salts: vector<u256>,
        risk_scores: vector<u8>,
        terms_params: vector<u256>, 
        lat_infos: vector<vector<u256>>
    ): u256 acquires Storage, Mapping, TimeGeneratedEventList{
        // need to check pause
        let storage = borrow_global_mut<Storage>(pool);
        let mapping = borrow_global_mut<Mapping>(pool);
        let tge_list = borrow_global_mut<TimeGeneratedEventList>(pool);

        let terms_params_length = vector::length(&terms_params);
        assert!( terms_params_length!= 0, 31);
        
        // let ids = loan_kernel_logic::loan_agreement_ids(debtors, terms_params, salts);
        
        let x = 0u64;
        let expected_assets_value = 0u256;

        let i = 0u64;
        let upper_bound_i = vector::length(&lat_infos);
        
        while (i < upper_bound_i) {
            // mint nft to pool
            let loans = vector::empty<LoanEntry>();
            let j = 0u64;
            let token_ids = vector::borrow(&lat_infos, i);
            let upper_bound_j = vector::length(token_ids);
            while (j < upper_bound_j) {
                let loan = LoanEntry {
                    debtor: *vector::borrow(&debtors, x),
                    principal_token_address: principal_token_address,
                    terms_param: *vector::borrow(&terms_params, x),
                    salt: *vector::borrow(&salts, x),
                    issuance_block_timestamp: (timestamp::now_seconds() as u256),
                    expiration_timestamp: *vector::borrow(&expiration_timestamps, x),
                    risk_score: *vector::borrow(&risk_scores, x),
                    asset_purpose: asset_purpose
                };
                vector::push_back(&mut loans, loan);
                x = x + 1;
                j = j + 1;
            };
            let collect_asset = collect_assets(
                storage,
                mapping,
                tge_list,
                *token_ids,
                loans
            );
            expected_assets_value = expected_assets_value + collect_asset;
            i = i + 1;
        };
        
        // before withdraw, check redeem, role originator, check min first loss
        assert!(storage.capital_reserve >= expected_assets_value, 35);
        underlying_token_factory::transfer_from(pool, sender, (expected_assets_value as u64), storage.underlying_currency);
        rebase(storage,mapping);
        return expected_assets_value
    }
    fun add_loan(storage: &mut Storage, mapping: &mut Mapping, token_id: u256, loan_entry: LoanEntry): u256{
        let loan_param = unpack_params_for_agreement_id(loan_entry);
        let nft_detail = NFTDetails {
            future_value: 0u128,
            maturity_date: (discounting::unique_day_timestamp(loan_param.term_end_unix_timestamp) as u128),
            risk: (loan_entry.risk_score as u64),
            debtor: loan_entry.debtor,
            principal_token_address: loan_entry.principal_token_address,
            salt: loan_entry.salt,
            issuance_block_timestamp: loan_entry.issuance_block_timestamp,
            expiration_timestamp: loan_entry.expiration_timestamp,
            /*
                asset_purpose = 0 --> LOAN
                asset_purpose = 1 --> INVOICE
            */
            asset_purpose: loan_entry.asset_purpose,
            terms_param: loan_entry.terms_param,
            principal_amount: loan_param.principal_amount,
            term_start_unix_timestamp: loan_param.term_start_unix_timestamp,
            term_end_unix_timestamp: loan_param.term_end_unix_timestamp,
            /*
                amortization_unit_type = 0 --> MINUTES
                amortization_unit_type = 1 --> HOURS
                amortization_unit_type = 2 --> DAYS
                amortization_unit_type = 3 --> WEEKS
                amortization_unit_type = 4 --> MONTHS
                amortization_unit_type = 5 --> YEARS
            */
            amortization_unit_type: loan_param.amortization_unit_type,
            term_length_in_amortization_units: loan_param.term_length_in_amortization_units,
            interest_rate: loan_param.interest_rate,
        };
        smart_table::add(&mut mapping.details, token_id, nft_detail);
        let risk_param = get_risk_score_by_idx(storage.risk_scores, (loan_entry.risk_score as u64));
        let principal_amount: u256 = loan_param.principal_amount;
        let _converted_interest_rate: u256;

        principal_amount = (principal_amount * (risk_param.advance_rate as u256)) / (ONE_HUNDRED_PERCENT);
        _converted_interest_rate = ONE + ((risk_param.interest_rate as u256) * ONE) / (ONE_HUNDRED_PERCENT * 31536000);  // 31536000 = 365 days

        let loan_count =  storage.loan_count;
        smart_table::add(&mut mapping.loan_to_nft, loan_count, token_id);
        storage.loan_count = loan_count + 1;

        let rate = smart_table::borrow_with_default<u256,Rate>(
            &mapping.rates, 
            _converted_interest_rate,
            &rate_default()
        );
        if (rate.rate_per_second == 0u256) {
            file_rate(mapping, 1u8, _converted_interest_rate, _converted_interest_rate);
        };
        set_rate(mapping,token_id, _converted_interest_rate);
        accrue(mapping, token_id);
        let balance = smart_table::borrow_mut_with_default<u256,u256>(&mut mapping.balances, token_id, 0u256);
        *balance = *balance + principal_amount;

        storage.balance = storage.balance + principal_amount;
        
        borrow(storage, mapping, token_id, principal_amount);
        inc_debt(mapping,token_id, principal_amount);

        principal_amount
    }
    fun set_rate(mapping: &mut Mapping, token_id: u256, converted_rate: u256){
        // TODO
        assert!(*smart_table::borrow_with_default(& mapping.pie, token_id, &0u256) == 0u256, 8);
        let rate = smart_table::borrow_with_default<u256,Rate>(
            &mapping.rates, 
            converted_rate,
            &rate_default()
        );
        assert!(rate.chi != 0u256, 8);
        smart_table::upsert<u256,u256>(&mut mapping.loan_rates, token_id, converted_rate);

        // Emit event later
    }
    fun accrue(mapping: &mut Mapping, token_id: u256){
        let loan_rate: u256 = *smart_table::borrow_with_default(& mapping.loan_rates, token_id, &0u256);

        let rate = smart_table::borrow_mut_with_default<u256,Rate>(
            &mut mapping.rates, 
            loan_rate,
            rate_default()
        );
        drip(rate);
    }
    fun drip(rate: &mut Rate) {
        let current = timestamp::now_seconds(); 
        if (current < rate.last_updated) return;
        let (chi, _): (u256,u256) = compounding(rate.chi, rate.rate_per_second, (rate.last_updated as u256), rate.pie);
        rate.chi = chi;
        let condition: bool = rate.penalty_rate_per_second != 0 && rate.time_start_penalty != 0 && current >= (rate.time_start_penalty as u64);
        if (condition){
            let last_updated = math::max_u256((rate.last_updated as u256), (rate.time_start_penalty as u256));
            let (penalty_chi, _): (u256,u256) = compounding(rate.penalty_chi,rate.penalty_rate_per_second,last_updated,rate.pie);
            rate.penalty_chi = penalty_chi; 
        };
        rate.last_updated = current;
    }

    #[view]
    fun compounding(chi: u256, rate_per_second: u256, last_updated: u256, pie: u256): (u256,u256) {
        assert!(chi != 0u256, 9);
        assert!((timestamp::now_seconds() as u256) >= last_updated, 9);
        let updated_chi = charge_interest(chi,rate_per_second,last_updated);
        (updated_chi, math::r_mul(updated_chi,pie) - math::r_mul(chi, pie))
    }

    #[view]
    fun charge_interest(interest_bearing_amount: u256,rate_per_second: u256, last_updated: u256): u256{
        let current: u256 = (timestamp::now_seconds() as u256); 
        if (current < last_updated) return interest_bearing_amount;
        interest_bearing_amount = math::r_mul(math::r_pow(rate_per_second,current - last_updated, ONE),interest_bearing_amount);
        interest_bearing_amount
    }
    fun borrow(storage: &mut Storage, mapping: &mut Mapping, token_id: u256, amount: u256): u256{
        let nnow: u256 = discounting::unique_day_timestamp((timestamp::now_seconds() as u256));
        let maturity_date = smart_table::borrow_with_default(
            &mapping.details,
            token_id,
            &nft_details_default()
        ).maturity_date;
        assert!((maturity_date as u256) >= nnow, 11);
        if (nnow > storage.last_nav_update) {
            calc_update_nav(storage,mapping);
        };

        let loan_rate: u256 = *smart_table::borrow_with_default(& mapping.loan_rates, token_id, &0u256);
        let rate = smart_table::borrow_mut_with_default<u256,Rate>(
            &mut mapping.rates, 
            loan_rate,
            rate_default()
        );

        let nft_detail = smart_table::borrow_mut_with_default(&mut mapping.details, token_id, nft_details_default());
        let fv = discounting::calc_future_value(
            rate.rate_per_second,
            amount,
            (maturity_date as u256),
            recovery_rate_pd(
                storage.risk_scores,
                nft_detail.risk,
                nft_detail.expiration_timestamp - nft_detail.issuance_block_timestamp
            )
        );

        nft_detail.future_value = nft_detail.future_value + (fv as  u128);

        let bucket = smart_table::borrow_mut_with_default(&mut mapping.buckets, (maturity_date as u256), 0u256);
        *bucket = *bucket + fv;

        let loan_detail = smart_table::borrow_mut_with_default(
            &mut mapping.loan_details, 
            token_id, 
            LoanDetails {
                borrowed: 0u128,
                auth_write_off: false
            }
        );
        loan_detail.borrowed = loan_detail.borrowed + (amount as u128);

        let nav_increase = discounting::calc_discount(storage.discount_rate, fv, nnow, (maturity_date as u256));
        storage.latest_discount = storage.latest_discount + nav_increase;

        let latest_discount_of_nav_assets = smart_table::borrow_mut_with_default(&mut mapping.latest_discount_of_nav_assets, token_id, 0u256);
        *latest_discount_of_nav_assets = *latest_discount_of_nav_assets + nav_increase;

        storage.latest_nav = storage.latest_nav + nav_increase;
        return nav_increase
    }
    fun calc_update_nav(storage: &mut Storage, mapping: &mut Mapping): u256 {
        let (total_discount, overdue, write_offs): (u256,u256,u256) = current_pvs(storage, mapping);
        let i = 0u64; 
        while ((i as u256) < storage.loan_count) {
            let token_id = *smart_table::borrow_with_default(&mapping.loan_to_nft, (i as u256), &0u256);
            let (td, ol, _) = current_av(storage, mapping, token_id);

            let overdue_loans_of_nav_assets = smart_table::borrow_mut_with_default(&mut mapping.overdue_loans_of_nav_assets, token_id, 0u256); 
            *overdue_loans_of_nav_assets = ol;

            let latest_discount_of_nav_assets = smart_table::borrow_mut_with_default(&mut mapping.latest_discount_of_nav_assets, token_id, 0u256); 
            *latest_discount_of_nav_assets = td;
    
            i = i+1;
        };
        storage.overdue_loans = overdue;
        storage.latest_discount = total_discount;

        storage.latest_nav = total_discount + overdue + write_offs;
        storage.last_nav_update = discounting::unique_day_timestamp((timestamp::now_seconds() as u256));
        return storage.latest_nav
    }
    fun current_av(storage: &mut Storage, mapping: &mut Mapping, token_id: u256): (u256,u256,u256) {
        let overdue = 0u256;
        let current_write_offs = 0u256;
        let(discount_rate, latest_discount_of_nav_assets_id, last_nav_update, overdue_loans_of_nav_assets_id)
            = (
                storage.discount_rate,
                *smart_table::borrow_with_default(&mapping.latest_discount_of_nav_assets, token_id, &0u256),
                storage.last_nav_update,
                *smart_table::borrow_with_default(&mapping.overdue_loans_of_nav_assets, token_id, &0u256),
            );
        if (is_loan_written_off(mapping,token_id)){
            let (exist_valid_write_off ,write_off_group_index) = current_valid_write_off_group(storage,mapping,token_id);
            let percentage = 0u128;
            if (exist_valid_write_off) 
                percentage = vector::borrow(&storage.write_off_groups, write_off_group_index).percentage;
            current_write_offs = math::r_mul(debt(mapping, token_id), (percentage as u256));
        };

        if (latest_discount_of_nav_assets_id == 0)
            return (0, overdue_loans_of_nav_assets_id, current_write_offs);
        
        let err_pv = 0u256;
        let nnow = discounting::unique_day_timestamp((timestamp::now_seconds() as u256));
        let nft_detail = smart_table::borrow_with_default(&mapping.details, token_id, &nft_details_default());
        let mat = discounting::unique_day_timestamp((nft_detail.maturity_date as u256));
        let condition: bool = mat >= last_nav_update && mat < nnow;
        if (condition) {
            let b: u256 = (nft_detail.future_value as u256) ;
            err_pv = math::r_mul(b, math::r_pow(discount_rate,nnow - mat, ONE));
            overdue = b;
        };
        return (
            math::secure_sub(
                math::r_mul(latest_discount_of_nav_assets_id, math::r_pow(discount_rate, nnow - last_nav_update, ONE)),
                err_pv
            ),
            overdue_loans_of_nav_assets_id + overdue,
            current_write_offs
        )
    }
    fun debt (mapping: &Mapping, token_id: u256):u256 {
        let loan_rate = *smart_table::borrow_with_default<u256,u256>(&mapping.loan_rates, token_id, &0u256);
        let pie = *smart_table::borrow_with_default<u256,u256>(&mapping.pie, token_id, &0u256);
        let rate = smart_table::borrow_with_default<u256,Rate>(
            &mapping.rates, 
            loan_rate,
            &rate_default()
        );
        let chi = charge_interest(rate.chi, rate.rate_per_second, (rate.last_updated as u256));
        let penalty_chi = charge_interest(rate.penalty_chi, rate.penalty_rate_per_second, (rate.last_updated as u256));
        if (penalty_chi == 0) return generic_logic::to_amount(chi,pie);
        return generic_logic::to_amount(penalty_chi, generic_logic::to_amount(chi,pie))
    }
    fun current_valid_write_off_group(storage: &Storage, mapping: & Mapping, token_id: u256): (bool, u64){
        let nft_detail = smart_table::borrow_with_default(&mapping.details, token_id, &nft_details_default());
        let maturity_date = nft_detail.maturity_date;
        let nnow = discounting::unique_day_timestamp((timestamp::now_seconds() as u256));
        let loan_risk_index: u64 = nft_detail.risk -1;
        let exist_valid_write_off = false;
        let last_valid_write_off = 0u64;

        let highest_overdue_days = 0u128;

        let write_off_groups_length: u64 = vector::length(&storage.write_off_groups); 
        let i = 0u64;
        while(i < write_off_groups_length){
            let write_off_group = vector::borrow(&storage.write_off_groups, i);
            let overdue_days = write_off_group.overdue_days;
            let condition: bool = write_off_group.risk_index == loan_risk_index &&
                overdue_days >= highest_overdue_days &&
                nnow >= (maturity_date as u256) + (overdue_days as u256) * 86400;
            if (!condition) continue;
            if (!exist_valid_write_off) exist_valid_write_off = true; 
            last_valid_write_off = i;
            highest_overdue_days = overdue_days;
            i = i+1;
        };
        return (exist_valid_write_off, last_valid_write_off)
    }
    fun is_loan_written_off(mapping: &Mapping, token_id: u256): bool{
        return *smart_table::borrow_with_default(&mapping.loan_rates, token_id, &0u256) >= WRITE_OFF_RATE_GROUP_START
    }
    fun current_pvs(storage: &Storage, mapping: &Mapping): (u256,u256,u256) {
        let (total_discount, overdue, write_offs) = (0u256, 0u256, 0u256);
        let (latest_discount, overdue_loans, discount_rate, last_nav_update): (u256,u256,u256,u256) 
            = (storage.latest_discount, storage.overdue_loans, storage.discount_rate, storage.last_nav_update);
        if (latest_discount == 0) 
            return (0, overdue_loans, current_write_offs(storage,mapping));
        let err_pv = 0u256;
        let nnow = discounting::unique_day_timestamp((timestamp::now_seconds() as u256));
        let i = last_nav_update;
        while(i < nnow){
            let b: u256 = *smart_table::borrow_with_default(&mapping.buckets, (i as u256), &0u256);
            if (b == 0) continue;
            err_pv = err_pv + math::r_mul(b, math::r_pow(discount_rate,nnow - i, ONE)); 
            overdue = overdue + b;

            i = i + 86400;
        };
        return (
            math::secure_sub(
                math::r_mul(latest_discount, math::r_pow(discount_rate, nnow - last_nav_update, ONE)),
                err_pv
            ),
            overdue_loans + overdue,
            current_write_offs(storage,mapping)
        )
    }
    fun current_write_offs(storage: &Storage, mapping: &Mapping): u256{
        let length: u64 = vector::length(&storage.write_off_groups);
        let sum = 0u256;
        let i = 0u64;
        while(i < length){
            let rate = smart_table::borrow_with_default<u256,Rate>(
                & mapping.rates, 
                WRITE_OFF_RATE_GROUP_START + (i as u256),
                &rate_default()
            );
            let write_off_groups: &WriteOffGroup = vector::borrow(&storage.write_off_groups, i); 
            sum = sum + math::r_mul(
                rate_debt(rate),
                (write_off_groups.percentage as u256)
            );
            i = i+1;
        };
        return sum
    }
    fun rate_debt(rate: & Rate): u256{
        let current = timestamp::now_seconds(); 
        let pie = rate.pie ;
        let chi = charge_interest(rate.chi, rate.rate_per_second, (rate.last_updated as u256));
        let penalty_chi = charge_interest(rate.penalty_chi, rate.penalty_rate_per_second, (rate.last_updated as u256));
        if (penalty_chi == 0) return generic_logic::to_amount(chi,pie);
        return generic_logic::to_amount(penalty_chi, generic_logic::to_amount(chi,pie))
    }
    fun recovery_rate_pd(risk_scores: vector<RiskScore>, risk_id: u64, term_length: u256): u256{
        let risk_param = get_risk_score_by_idx(risk_scores, risk_id);
        return math::secure_sub(
            ONE,
            (ONE * (risk_param.probability_of_default as u256) * (risk_param.loss_given_default as u256) * term_length) /
            (ONE_HUNDRED_PERCENT * ONE_HUNDRED_PERCENT * 31536000)
        )
    }
    fun inc_debt(mapping: &mut Mapping, token_id: u256, currency_amount: u256){
        let current = timestamp::now_seconds(); 
        let loan_rate: u256 = *smart_table::borrow_with_default(& mapping.loan_rates, token_id, &0u256);
        let rate = smart_table::borrow_mut_with_default<u256,Rate>(
            &mut mapping.rates, 
            loan_rate,
            rate_default()
        );
        assert!(current == rate.last_updated, 10);
        // let penalty_chi = rate.penalty_chi;
        // if (penalty_chi > 0) {
        //     currency_amount = generic_logic::to_pie(penalty_chi,currency_amount);
        // };
        let pie_amount = generic_logic::to_pie(rate.chi,currency_amount);

        let pie = smart_table::borrow_mut_with_default<u256,u256>(&mut mapping.pie, token_id, 0u256); 
        *pie = *pie + pie_amount;
        rate.pie = rate.pie + pie_amount;

        // need emit event here
    }
    fun change_senior_asset(storage: &mut Storage, mapping: &mut Mapping, senior_supply: u256, senior_redeem: u256){
        let nav = current_nav(storage,mapping);
        let reserve = reserve(storage);
        let (senior_debt, senior_balance) = rebase_logic::rebase(
            nav,
            reserve,
            rebase_logic::calc_expected_senior_asset(
                senior_redeem,
                senior_supply,
                storage.senior_balance,
                drip_senior_debt(storage)
            )
        );
        storage.senior_debt = senior_debt;
        storage.senior_balance = senior_balance;
    }
    fun storage_default(): Storage {
        return Storage {
            validator_required: false,
            first_asset_timestamp: 0u64,
            risk_scores: vector::empty<RiskScore>(),
            nft_assets: vector::empty<NFTAsset>(),
            // tge_address: @0x0,
            // second_tge_address: @0x0,
            sot_token: @0x0,
            jot_token: @0x0,
            underlying_currency: @0x0,
            income_reserve: 0u256,
            capital_reserve: 0u256,
            min_first_loss_cushion: 0u32,
            opening_block_timestamp: 0u64,
            // pot: @0x0,
            interest_rate_sot: 0u32,
            total_asset_repaid_currency: 0u256,
            debt_ceiling: 0u256,
            loan_count: 0u256,
            balance: 0u256,
            write_off_groups: vector::empty<WriteOffGroup>(),
            discount_rate: 0u256,
            latest_nav: 0u256,
            latest_discount: 0u256,
            last_nav_update: 0u256,
            overdue_loans: 0u256,
            total_principal_repaid: 0u256,
            total_interest_repaid: 0u256,
            senior_debt: 0u256,
            senior_balance: 0u256,
            last_update_senior_interest: 0u64,
        }
    }
    fun mapping_default(): Mapping {
        return Mapping {
            rates: smart_table::new<u256, Rate>(),
            pie: smart_table::new<u256, u256>(),
            loan_rates: smart_table::new<u256,u256>(),
            balances: smart_table::new<u256,u256>(),
            details: smart_table::new<u256, NFTDetails>(),
            loan_details: smart_table::new<u256, LoanDetails>(),
            buckets: smart_table::new<u256,u256>(),
            latest_discount_of_nav_assets: smart_table::new<u256, u256>(),
            overdue_loans_of_nav_assets: smart_table::new<u256,u256>(),
            loan_to_nft: smart_table::new<u256,u256>(),
            underlying_currency_raised_by_investor_sot: smart_table::new<address, u256>(),
            underlying_currency_raised_by_investor_jot: smart_table::new<address, u256>(),
        }
    }
    fun rate_default(): Rate {
        return Rate {
            pie: 0u256,
            chi: 0u256,
            rate_per_second: 0u256,
            penalty_rate_per_second: 0u256,
            penalty_chi: 0u256,
            last_updated: 0u64,
            time_start_penalty: 0u32
        }
    }
    fun nft_details_default(): NFTDetails {
        return NFTDetails {
            future_value: 0u128,
            maturity_date: 0u128,
            risk: 0u64,
            debtor: @0x0,
            principal_token_address: @0x0,
            salt: 0u256,
            issuance_block_timestamp: 0u256,
            expiration_timestamp: 0u256,
            asset_purpose: 0u8,
            terms_param: 0u256,
            principal_amount: 0u256,
            term_start_unix_timestamp: 0u256,
            term_end_unix_timestamp: 0u256,
            amortization_unit_type: 0u8,
            term_length_in_amortization_units: 0u256,
            interest_rate: 0u256,
        }
    }
    // For TGE
    public (friend) fun set_up_tge_for_sot(pool_signer: &signer, interest_rate: u32, opening_time: u64, total_cap: u256, min_bid_amount: u256) acquires Storage, TimeGeneratedEventList{
        // need to check only issuer later 
        let pool = signer::address_of(pool_signer);
        let storage = borrow_global_mut<Storage>(pool);
        let tge_list = borrow_global_mut<TimeGeneratedEventList>(pool);

        let underlying_currency = storage.underlying_currency;
        let sot_metadata_address = token_factory::create_token(
            pool_signer,
            utf8(b"Senior Obligation Tranche Token"),
            utf8(b"SOT"),
            underlying_token_factory::decimals(underlying_currency),
            utf8(b"http://example.com/favicon.ico"),
            utf8(b"http://example.com"),
            underlying_currency,
            0u8,
        );
        set_interest_rate_sot(storage, interest_rate);

        // Assert that the asset is not already added
        assert!(!smart_table::contains(&tge_list.value, 0u8), 20);
        
        let tge = TimeGeneratedEvent{
            token: sot_metadata_address,
            has_started: false,
            first_note_token_minted_timestamp: 0u64,
            currency_raised: 0u256,
            token_raised: 0u256,
            total_cap: total_cap,
            min_bid_amount: min_bid_amount,
            initial_amount: 0u256,
            opening_time: opening_time
        };
        smart_table::add(&mut tge_list.value, 0u8, tge);
        tge_list.count = tge_list.count + 1;

        storage.sot_token = sot_metadata_address;
    }
    public (friend) fun set_up_tge_for_jot(pool_signer: &signer, opening_time: u64, total_cap: u256, min_bid_amount: u256, initial_amount: u256) acquires Storage, TimeGeneratedEventList{
        // need to check only issuer later 
        let pool = signer::address_of(pool_signer);
        let storage = borrow_global_mut<Storage>(pool);
        let tge_list = borrow_global_mut<TimeGeneratedEventList>(pool);

        let underlying_currency = storage.underlying_currency;
        let jot_metadata_address = token_factory::create_token(
            pool_signer,
            utf8(b"Junior Obligation Tranche Token"),
            utf8(b"JOT"),
            underlying_token_factory::decimals(underlying_currency),
            utf8(b"http://example.com/favicon.ico"),
            utf8(b"http://example.com"),
            underlying_currency,
            1u8,
        );

        // Assert that the asset is not already added
        assert!(!smart_table::contains(&tge_list.value, 1u8), 20);
        
        let tge = TimeGeneratedEvent{
            token: jot_metadata_address,
            has_started: true,
            first_note_token_minted_timestamp: 0u64,
            currency_raised: 0u256,
            token_raised: 0u256,
            total_cap: total_cap,
            min_bid_amount: min_bid_amount,
            initial_amount: initial_amount,
            opening_time: opening_time
        };
        smart_table::add(&mut tge_list.value, 1u8, tge);
        tge_list.count = tge_list.count + 1;

        storage.jot_token = jot_metadata_address;
    }
    fun set_interest_rate_sot(storage: &mut Storage,interest_rate_sot: u32){
        storage.interest_rate_sot = interest_rate_sot;
    }
    fun calc_token_price(storage: &Storage, mapping: &Mapping): (u256, u256){
        let sot_token = storage.sot_token;
        let jot_token = storage.jot_token;
        let decimal = math::pow(10,(underlying_token_factory::decimals(storage.underlying_currency) as u256));
        assert!(sot_token != @0x0, 21);
        assert!(jot_token != @0x0, 21);

        let (senior_token_price, junior_token_price) = rebase_logic::calc_token_price(
            current_nav(storage, mapping),
            reserve(storage),
            senior_debt(storage),
            storage.senior_balance,
            token_factory::supply(sot_token),
            token_factory::supply(jot_token)
        );
        return (
            senior_token_price * decimal / ONE,
            junior_token_price * decimal / ONE,
        ) 
    }
    // type_of_token = 0 --> sot
    // type_of_token = 1 --> jot
    public (friend) fun buy_token(sender: &signer ,pool: address, beneficiary: address, type_of_token: u8, currency_amount: u256): u256 acquires Storage, Mapping, TimeGeneratedEventList{
        // check open and set later value
        // need to optimize later
        let storage = borrow_global_mut<Storage>(pool);
        let mapping = borrow_global_mut<Mapping>(pool);
        let tge_list = borrow_global_mut<TimeGeneratedEventList>(pool);
        let payer = signer::address_of(sender);

        let token_amount = 0u256;
        let (sot_price, jot_price) = calc_token_price(storage,mapping);
        if (type_of_token == 0){
            let token_price = sot_price;
            assert!(token_price != 0, 22);
            token_amount = currency_amount * math::pow(10, (underlying_token_factory::decimals(storage.underlying_currency) as u256)) / token_price;
            // TODO validate purchase

            // update state
            let tge_sot = smart_table::borrow_mut_with_default(&mut tge_list.value, 0u8, time_generate_event_default());
            tge_sot.currency_raised = tge_sot.currency_raised + currency_amount;
            tge_sot.token_raised = tge_sot.token_raised + token_amount;
            
            let raised_by_investor_sot = smart_table::borrow_mut_with_default(&mut mapping.underlying_currency_raised_by_investor_sot, beneficiary, 0u256);
            *raised_by_investor_sot = *raised_by_investor_sot + currency_amount;

            // need check debt ceiling
            
            underlying_token_factory::transfer_from(payer, pool, (currency_amount as u64), storage.underlying_currency);
            token_factory::mint(pool, beneficiary, (token_amount as u128), storage.sot_token);

            if (token_factory::supply(storage.sot_token) == 0) {
                tge_sot.first_note_token_minted_timestamp = timestamp::now_seconds();
                set_up_opening_block_timestamp(storage, tge_sot.first_note_token_minted_timestamp);
            };
            change_senior_asset(storage, mapping, currency_amount,0);
        };
        if (type_of_token == 1){
            let token_price = jot_price;
            assert!(token_price != 0, 22);
            token_amount = currency_amount * math::pow(10, (underlying_token_factory::decimals(storage.underlying_currency) as u256)) / token_price;
            // TODO validate purchase

            // update state
            let tge_jot = smart_table::borrow_mut_with_default(&mut tge_list.value, 1u8, time_generate_event_default());
            tge_jot.currency_raised = tge_jot.currency_raised + currency_amount;
            tge_jot.token_raised = tge_jot.token_raised + token_amount;
            
            let raised_by_investor_jot = smart_table::borrow_mut_with_default(&mut mapping.underlying_currency_raised_by_investor_sot, beneficiary, 0u256);
            *raised_by_investor_jot = *raised_by_investor_jot + currency_amount;

            // need check debt ceiling
            
            underlying_token_factory::transfer_from(payer, pool, (currency_amount as u64), storage.underlying_currency);
            token_factory::mint(pool, beneficiary, (token_amount as u128), storage.jot_token);

            if (token_factory::supply(storage.jot_token) == 0) {
                tge_jot.first_note_token_minted_timestamp = timestamp::now_seconds();
                set_up_opening_block_timestamp(storage, tge_jot.first_note_token_minted_timestamp);
            };
            change_senior_asset(storage, mapping, 0, 0);
        };

        storage.capital_reserve = storage.capital_reserve + currency_amount;
        return token_amount
    }
    fun set_up_opening_block_timestamp(storage: &mut Storage, first_note_token_minted_timestamp: u64){
        let first_asset_timestamp = storage.first_asset_timestamp;
        if (first_note_token_minted_timestamp == 0 || first_asset_timestamp == 0) return;
        if (first_asset_timestamp > first_note_token_minted_timestamp) {
            storage.opening_block_timestamp = first_asset_timestamp;
            return
        };
        if (first_note_token_minted_timestamp > first_asset_timestamp) {
            storage.opening_block_timestamp = first_note_token_minted_timestamp;
            return
        };

    }
    fun debt_with_chi(mapping: &mut Mapping, loan: u256, chi: u256, penalty_chi: u256): u256 {
        if (penalty_chi == 0) {
            return generic_logic::to_amount(
                chi,
                *smart_table::borrow_with_default(& mapping.pie, loan, &0u256)
            )
        };
        return generic_logic::to_amount(
            penalty_chi,
            generic_logic::to_amount(
                chi,
                *smart_table::borrow_with_default(& mapping.pie, loan, &0u256)
            )
        )
    }
    fun dec_debt(mapping: &mut Mapping, token_id: u256, currency_amount: u256) {
        let loan_rate = *smart_table::borrow_with_default(& mapping.loan_rates, token_id, &0u256);
        let rate = smart_table::borrow_mut_with_default<u256,Rate>(
            &mut mapping.rates, 
            loan_rate,
            rate_default()
        );
        assert!(timestamp::now_seconds() == rate.last_updated, 51);

        let penalty_chi = rate.penalty_chi;
        if (penalty_chi > 0) {
            currency_amount = generic_logic::to_pie(penalty_chi, currency_amount);
        };
        let pie_amount = generic_logic::to_pie(rate.chi, currency_amount);
        rate.pie = rate.pie - pie_amount;
        let pie = smart_table::borrow_mut_with_default<u256,u256>(&mut mapping.pie, token_id, 0u256); 
        *pie = *pie - pie_amount;
    }
    fun decrease_loan(storage: &mut Storage, mapping: &mut Mapping, token_id: u256, amount: u256) {
        let loan_rate = *smart_table::borrow_with_default(& mapping.loan_rates, token_id, &0u256);
        assert!(loan_rate >= WRITE_OFF_RATE_GROUP_START, 50);
        let write_off_group_index = ((loan_rate - WRITE_OFF_RATE_GROUP_START) as u64);
        let percentage = vector::borrow(&storage.write_off_groups, write_off_group_index).percentage;
        // make sure percentage < 2 ** 128

        storage.last_nav_update = math::secure_sub(
            storage.last_nav_update,
            math::r_mul(
                amount,
                (percentage as u256)        
            )
        );
        dec_debt(mapping, token_id, amount);
    }
    fun repay_loans_nav(storage: &mut Storage, mapping: &mut Mapping, token_ids: vector<u256>, amounts: vector<u256>):(vector<u256>, vector<u256>) {
        let nnow = discounting::unique_day_timestamp((timestamp::now_seconds() as u256));
        let token_ids_length = vector::length(&token_ids);
        let repay_amounts = vector::empty<u256>();
        let previous_debts = vector::empty<u256>();
        let i = 0u64; 
        while (i < token_ids_length) {
            let token_id = *vector::borrow(&token_ids, i);
            let amount = *vector::borrow(&amounts, i);

            accrue(mapping, token_id);
            if (nnow > storage.last_nav_update) {
                calc_update_nav(storage,mapping);
            };

            // In case of successful repayment the latestNAV is decreased by the repaid amount
            let nft_detail = smart_table::borrow_with_default(&mut mapping.details, token_id, &nft_details_default());
            let maturity_date = nft_detail.maturity_date;
            let current_debt = debt(mapping, token_id);
            if (amount > current_debt) {
                amount = current_debt;
            };
            vector::push_back(&mut repay_amounts, amount);
            vector::push_back(&mut previous_debts, current_debt);
            
            // case 1: repayment of a written-off loan
            if (is_loan_written_off(mapping, token_id)){
                decrease_loan(storage,mapping,token_id, amount);
                continue;
            };
            
            
            let pre_fv =  (nft_detail.future_value as u256);
            // in case of partial repayment, compute the fv of the remaining debt and add to the according fv bucket
            let loan_rate: u256 = *smart_table::borrow_with_default(& mapping.loan_rates, token_id, &0u256);
            let rate = smart_table::borrow_mut_with_default<u256,Rate>(
                &mut mapping.rates, 
                loan_rate,
                rate_default()
            );

            let fv_decrease = pre_fv;
            let fv = 0u256;
            let debt = current_debt - amount;
            if (debt != 0){
                let fv = discounting::calc_future_value(
                    rate.rate_per_second,
                    debt,
                    (maturity_date as u256),
                    recovery_rate_pd(
                        storage.risk_scores,
                        nft_detail.risk,
                        nft_detail.expiration_timestamp - nft_detail.issuance_block_timestamp
                    )
                );
                fv_decrease = math::secure_sub(pre_fv, fv);
                let mut_nft_detail = smart_table::borrow_mut_with_default(&mut mapping.details, token_id, nft_details_default());
                mut_nft_detail.future_value = (fv as u128);
            };

            // case 2: repayment of a loan before or on maturity date
            if((maturity_date as u256) >= nnow) {
                let bucket = smart_table::borrow_mut_with_default(&mut mapping.buckets, (maturity_date as u256), 0u256);
                *bucket = *bucket - fv_decrease;
                let discount_decrease = discounting::calc_discount(
                    storage.discount_rate,
                    fv_decrease,
                    nnow,
                    (maturity_date as u256)
                );
                storage.latest_discount = math::secure_sub(storage.latest_discount, discount_decrease);
                let latest_discount_of_nav_assets = smart_table::borrow_mut_with_default(&mut mapping.latest_discount_of_nav_assets, token_id, 0u256);
                *latest_discount_of_nav_assets = math::secure_sub(*latest_discount_of_nav_assets, discount_decrease);
                storage.latest_nav = math::secure_sub(storage.latest_nav, discount_decrease); 
            } else {
                storage.overdue_loans = storage.overdue_loans - fv_decrease;
                let overdue_loans_of_nav_assets = smart_table::borrow_mut_with_default(&mut mapping.overdue_loans_of_nav_assets, token_id, 0u256);
                *overdue_loans_of_nav_assets = *overdue_loans_of_nav_assets - fv_decrease;
                storage.latest_nav = math::secure_sub(storage.latest_nav, fv_decrease); 
            };
            dec_debt(mapping, token_id, amount);
            i = i + 1;
        };
        return (repay_amounts, previous_debts)
    }
    fun repay_loans(storage: &mut Storage, mapping: &mut Mapping, token_ids: vector<u256>, amounts: vector<u256>): (vector<u256>, vector<u256>) {
        let token_ids_length = vector::length(&token_ids);
        let last_outstanding_debt = vector::empty<u256>();
        let i = 0u64;
        while(i < token_ids_length) {
            // let (chi, penalty_chi) = 
            let loan_rate: u256 = *smart_table::borrow_with_default(& mapping.loan_rates, *vector::borrow(&token_ids, i), &0u256);
            let rate = smart_table::borrow_mut_with_default<u256,Rate>(
                &mut mapping.rates, 
                loan_rate,
                rate_default()
            );
            vector::push_back(
                &mut last_outstanding_debt,
                debt_with_chi(mapping, *vector::borrow(&token_ids, i), rate.chi, rate.penalty_chi)
            );
            i = i + 1;
        };
        let (repay_amounts, previous_debts) = repay_loans_nav(storage,mapping, token_ids, amounts);
        let total_interest_repaid = 0u256;
        let total_principal_repaid = 0u256;
        
        i = 0u64;
        while(i < token_ids_length) {
            let interest_amount = *vector::borrow(&previous_debts, i) - *vector::borrow(&last_outstanding_debt, i);
            let repay_amount = *vector::borrow(&repay_amounts, i);
            if (repay_amount < interest_amount) {
                total_interest_repaid = total_interest_repaid + repay_amount;
            }else{
                total_interest_repaid = total_interest_repaid + interest_amount;
                total_interest_repaid = repay_amount - interest_amount;
            };
            i = i + 1;
        };
        storage.income_reserve = storage.income_reserve + total_interest_repaid;
        storage.capital_reserve = storage.capital_reserve + total_principal_repaid;
        return (repay_amounts, previous_debts)
    }
    fun do_repay(storage: &mut Storage, mapping: &mut Mapping, from: address, pool: address, token_ids: vector<u256>, amounts: vector<u256>){
        let total_repaid = 0u256;
        let (repay_amounts, previous_debts) = repay_loans_nav(storage, mapping, token_ids, amounts);
        let repay_amounts_length = vector::length(&repay_amounts);
        let i = 0u64;
        while (i < repay_amounts_length){
            let token_id = *vector::borrow(&token_ids, i);
            let repay_amount = *vector::borrow(&repay_amounts, i);
            let outstanding_amount = debt(mapping, token_id);
            // check if repay = debt, remove loan
            total_repaid = total_repaid + repay_amount;
            //emit repay event
            event::emit(AssetRepaid {
                pool: pool,
                originator: from,
                token_id: token_id,
                underlying_currency: storage.underlying_currency,
                repay_amount: repay_amount,
                outstanding_amount: outstanding_amount
            });

            i = i + 1;
        };
        underlying_token_factory::transfer_from(from, pool, (total_repaid as u64), storage.underlying_currency);
        storage.total_asset_repaid_currency = storage.total_asset_repaid_currency + total_repaid; 
    }
    public (friend) fun repay(sender: &signer, pool: address, token_ids: vector<u256>, amounts: vector<u256>) acquires Storage, Mapping{
        // TODO need to check owner of tokenIds
        let storage = borrow_global_mut<Storage>(pool);
        let mapping = borrow_global_mut<Mapping>(pool);
        do_repay(storage,mapping, signer::address_of(sender), pool, token_ids, amounts);
        rebase(storage,mapping);
    }
    fun time_generate_event_default(): TimeGeneratedEvent {
        return TimeGeneratedEvent {
            token: @0x0,
            has_started: false,
            first_note_token_minted_timestamp: 0u64,
            currency_raised: 0u256,
            token_raised: 0u256,
            total_cap: 0u256,
            min_bid_amount: 0u256,
            initial_amount: 0u256,
            opening_time: 0u64 
        }
    }
    fun time_generate_event_list_default(): TimeGeneratedEventList {
        return TimeGeneratedEventList {
            value: smart_table::new<u8, TimeGeneratedEvent>(),
            count: 0
        }
    }

    // getter
    public fun get_storage(pool: address): Storage acquires Storage {
        return *borrow_global<Storage>(pool)
    }

    // getter
    #[view]
    public (friend) fun get_current_nav(pool: address): u256 acquires Storage, Mapping{
        let storage = borrow_global<Storage>(pool);
        let mapping = borrow_global<Mapping>(pool);
        return current_nav(storage,mapping)
    }
    #[view]
    public (friend) fun get_capital_reserve(pool: address): u256 acquires Storage{
        let storage = borrow_global<Storage>(pool);
        return storage.capital_reserve
    }
    #[view]
    public (friend) fun get_reserve(pool: address): u256 acquires Storage{
        let storage = borrow_global<Storage>(pool);
        return storage.capital_reserve + storage.income_reserve
    }
    #[view]
    public (friend) fun get_interest_rate_sot(pool: address): u32 acquires Storage{
        let storage = borrow_global<Storage>(pool);
        return storage.interest_rate_sot
    }
    #[view]
    public (friend) fun get_token_price(pool: address):(u256, u256)  acquires Storage, Mapping{
        let storage = borrow_global<Storage>(pool);
        let mapping = borrow_global<Mapping>(pool);
        return calc_token_price(storage,mapping)
    }
    #[view]
    public (friend) fun get_sot_capacity(pool: address): u256 acquires TimeGeneratedEventList {
        let tge_list = borrow_global<TimeGeneratedEventList>(pool);
        let tge_sot = smart_table::borrow_with_default(&tge_list.value, 0u8, &time_generate_event_default());
        return tge_sot.total_cap
    }
    #[view]
    public (friend) fun get_jot_capacity(pool: address): u256 acquires TimeGeneratedEventList {
        let tge_list = borrow_global<TimeGeneratedEventList>(pool);
        let tge_jot = smart_table::borrow_with_default(&tge_list.value, 1u8, &time_generate_event_default());
        return tge_jot.total_cap
    }
    #[view]
    public (friend) fun get_total_sot(pool: address): u256 acquires Storage {
        let storage = borrow_global<Storage>(pool);
        return token_factory::supply(storage.sot_token)
    }
    #[view]
    public (friend) fun get_total_jot(pool: address): u256 acquires Storage {
        let storage = borrow_global<Storage>(pool);
        return token_factory::supply(storage.jot_token)
    }
    #[view]
    public (friend) fun get_debt(pool: address, token_id: u256): u256 acquires Mapping {
        let mapping = borrow_global<Mapping>(pool);
        return debt(mapping, token_id)
    }
    #[view]
    public (friend) fun get_debts(pool: address, token_ids: vector<u256>): vector<u256> acquires Mapping {
        let debts = vector::empty<u256>();
        let mapping = borrow_global<Mapping>(pool);
        let token_ids_length = vector::length(&token_ids);
        let i = 0u64;
        while (i < token_ids_length) {
            vector::push_back(
                &mut debts,
                debt(mapping, *vector::borrow(&token_ids, i))
            );
            i = i + 1; 
        };
        return debts
    }
}