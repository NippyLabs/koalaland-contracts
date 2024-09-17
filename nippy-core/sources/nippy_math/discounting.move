module nippy_math::discounting {
    use aptos_framework::timestamp;

    use nippy_math::math;

    /// @dev Ignoring leap years
    const SECONDS_PER_YEAR: u256 = 365 * 24 * 3600;

    const SECONDS_PER_DAY: u256 = 365 * 24 * 3600;

    /// Calculation results in overflow
    const EOVERFLOW: u64 = 1;

    /// Cannot divide by zero
    const EDIVISION_BY_ZERO: u64 = 2;

    public fun second_per_day(): u256 {
        SECONDS_PER_DAY
    }
    
    public fun second_per_year(): u256 {
        SECONDS_PER_YEAR
    }

    /// @notice calculates the discount for a given loan
    /// @param discountRate the discount rate
    /// @param fv the future value of the loan
    /// @param normalizedBlockTimestamp the normalized block time (each day to midnight)
    /// @param maturityDate the maturity date of the loan
    /// @return result discount for the loan
    public fun calc_discount(
        discountRate: u256,
        fv: u256,
        normalizedBlockTimestamp: u256,
        maturityDate: u256
    ): u256 {
        assert!(normalizedBlockTimestamp <= maturityDate, EOVERFLOW);
        return math::r_div(fv, math::r_pow(discountRate, maturityDate - normalizedBlockTimestamp, math::one()))
    }



    /// @notice calculate the future value based on the amount, maturityDate interestRate and recoveryRate
    /// @param loanInterestRate the interest rate of the loan
    /// @param amount of the loan (principal)
    /// @param maturityDate the maturity date of the loan
    /// @param recoveryRatePD the recovery rate together with the probability of default of the loan
    /// @return fv future value of the loan
    public fun calc_future_value(
        loanInterestRate: u256,
        amount: u256,
        maturityDate: u256,
        recoveryRatePD: u256
    ): u256 {
        let nnow = unique_day_timestamp((timestamp::now_seconds() as u256));
        let timeRemaining = 0u256;
        if (maturityDate > nnow) {
            timeRemaining = maturityDate - nnow;
        };

        return math::r_mul(math::r_mul(math::r_pow(loanInterestRate, timeRemaining, math::one()), amount), recoveryRatePD)
    }

    public fun unique_day_timestamp(timestamp: u256): u256{
        return (SECONDS_PER_DAY) * (timestamp / (SECONDS_PER_DAY))
    }
}
