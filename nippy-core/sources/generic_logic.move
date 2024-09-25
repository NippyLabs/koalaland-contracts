module nippy_pool::generic_logic {
    use nippy_math::math;
    public fun unpack_parameters_from_bytes(parameters: u256): (u256,u256,u256,u256,u256){
        // 32 = 12 + 12 + 4 + 1 + 1 + 2 
        let principal_amount: u256 = parameters >> 160;
        let term_length_in_amortization_units: u256 = (parameters << 96) >> 160;
        let interest_rate: u256 = (parameters << 192) >> 224;
        let amortization_unit_type: u256 = (parameters << 224) >> 248;
        let grace_period_in_days: u256 = (parameters << 232) >> 248;
        (principal_amount,term_length_in_amortization_units , interest_rate, amortization_unit_type , grace_period_in_days)
    }

    public fun get_amortization_unit_length_in_seconds(amortization_unit_type: u256): u256 {
        assert!(amortization_unit_type <= 5, 7);
        let in_seconds: u256 = 0;
        if (amortization_unit_type == 0) {
            in_seconds = 60;  // 1 minutes
        } else if (amortization_unit_type == 1) {
            in_seconds = 3600; // 1 hour
        } else if (amortization_unit_type == 2) {
            in_seconds = 86400; // 1 day
        } else if (amortization_unit_type == 3) {
            in_seconds = 604800;  // 7 days
        } else if (amortization_unit_type == 4) {
            in_seconds = 2592000; // 30 days
        } else if (amortization_unit_type == 5) {
            in_seconds = 31536000; //365 days;
        };
        return in_seconds
    }

    public fun to_pie(chi: u256, amount: u256): u256 {
        math::r_div_up(amount,chi)
    }
    public fun to_amount(chi: u256, pie: u256): u256 {
        math::r_mul(pie, chi)
    }
    // #[test_only]
    // use std::debug::print;
    // #[test]
    // fun hihi() {
    //     let value: u256 = 146150163733090291820368483271628301965593254297784467483686785384448;
    //     let (x,y,z,t,k) = unpack_parameters_from_bytes(value);
    //     print(&x);
    //     print(&y);
    //     print(&z);
    //     print(&t);
    //     print(&k);
    // }
}