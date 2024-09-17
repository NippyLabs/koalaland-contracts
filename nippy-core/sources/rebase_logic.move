module nippy_pool::rebase_logic {
    use nippy_math::math;
    const U256_MAX: u256 =
            0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;
    public fun calc_expected_senior_asset(senior_redeem: u256, senior_supply: u256, senior_balance: u256, senior_debt: u256): u256{
        assert!(senior_debt <= U256_MAX - senior_balance, 20);
        assert!(senior_supply <= U256_MAX - senior_balance - senior_debt, 20);
        assert!(senior_redeem <=  senior_balance + senior_debt + senior_supply, 20);
        return (senior_debt + senior_balance + senior_supply - senior_redeem)
    }
    public fun calc_senior_asset(senior_debt: u256, senior_balance: u256): u256{
        assert!(senior_debt <= U256_MAX - senior_balance, 20);
        return (senior_debt + senior_balance)
    }
    public fun calc_senior_ratio(senior_asset: u256, nav: u256, reserve: u256): u256{
        assert!(nav <= U256_MAX - reserve, 20);
        let assets = nav + reserve;
        if (assets == 0)    
            return 0;
        return math::r_div(senior_asset,assets)
    }
    public fun rebase(nav: u256, reserve: u256, senior_asset: u256): (u256, u256){
        let senior_ratio = calc_senior_ratio(senior_asset, nav, reserve);
        if (senior_ratio > math::one())
            senior_ratio = math::one();
        let senior_balance = 0u256;
        let senior_debt = math::r_mul(nav, senior_ratio);
        if (senior_debt > senior_asset) {
            senior_debt = senior_asset;
        } else {
            senior_balance = senior_asset - senior_debt;
        };
        return (senior_debt, senior_balance)
    }
    public fun calc_senior_token_price(nav: u256, reserve: u256, senior_debt: u256, senior_balance: u256, sot_total_supply: u256): u256{
        let condition: bool = (nav == 0 && reserve == 0 ) || sot_total_supply <= 2;
        if (condition) 
            return math::one();
        let pool_value = nav + reserve;
        let senior_asset_value = calc_senior_asset(senior_debt,senior_balance);
        if (pool_value < senior_asset_value) {
            senior_asset_value = pool_value;
        };
        return math::r_div(senior_asset_value, sot_total_supply)
    }
    public fun calc_junior_token_price(nav: u256, reserve: u256, senior_debt: u256, senior_balance: u256, jot_total_supply: u256): u256 {
        let condition: bool = (nav == 0 && reserve == 0 ) || jot_total_supply <= 2;
        if (condition) 
            return math::one();
        let pool_value = nav + reserve;
        let senior_asset_value = calc_senior_asset(senior_debt,senior_balance);
        if (pool_value < senior_asset_value) 
            return 0;
        return math::r_div(pool_value - senior_asset_value, jot_total_supply)
    }
    public fun calc_token_price(nav: u256, reserve: u256, senior_debt: u256, senior_balance: u256, sot_total_supply: u256, jot_total_supply: u256): (u256,u256){
        return (
            calc_senior_token_price(nav,reserve,senior_debt, senior_balance, sot_total_supply),
            calc_junior_token_price(nav,reserve,senior_debt, senior_balance, jot_total_supply)
        )
    }

}