module nippy_math::math {
    const ONE: u256 = 1_000_000_000_000_000_000_000_000_000; // 10^27

    const U256_MAX: u256 =
        0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;

    /// Overflow resulting from a calculation
    const EOVERFLOW: u64 = 1;
    /// Cannot divide by 0
    const EDIVISION_BY_ZERO: u64 = 2;

    public fun one(): u256 {
        ONE
    }
    public fun type_u64_max(): u64 {
        return 18446744073709551615
    }
    /// @param a 
    /// @param b 
    /// @return z = (a * b) / ONE
    public fun r_mul(a: u256, b: u256): u256 {
        if (a == 0 || b == 0) {
            return 0
        };
        assert!(a <= U256_MAX / b, EOVERFLOW);
        (a * b ) / ONE
    }

    /// @param a 
    /// @param b 
    /// @return z = ((a * ONE) + b/2 ) / b
    public fun r_div(a: u256, b: u256): u256 {
        assert!(b > 0, EDIVISION_BY_ZERO);
        if (a == 0) {
            return 0
        };
        assert!(a <= (U256_MAX - b / 2) / ONE, EOVERFLOW);
        (a * ONE + b / 2) / b
    }

    /// @notice Multiplies two number, rounding up to the nearest 
    /// @param a 
    /// @param b 
    /// @return z = ((a * ONE) + (b -1)) / b
    public fun r_div_up(a: u256, b: u256): u256 {
        assert!(b > 0, EDIVISION_BY_ZERO);
        if (a == 0) {
            return 0
        };
        assert!(a <= (U256_MAX - b + 1 ) / ONE, EOVERFLOW);
        ((a * ONE) + (b -1)) / b
    }
    /// @param a in 1ebase
    /// @param n
    /// @param base
    /// @return z = a**n in 1ebase
    public fun r_pow(x: u256, n: u256, base: u256): u256{
        let _z: u256 = 0;
        if(x == 0 && n ==0) {
            _z = base;
            return _z
        };
        if (x == 0){
            _z = 0;
            return _z
        };

        let nIsEven = n % 2;
        if (nIsEven == 0) {
            _z = base;
        } else {
            _z = x;
        };
        let  half = base / 2;
        n  = n / 2;
        loop
        {
            
            let xx = x * x;
            let xxRound = xx + half;
            x = xxRound / base;
            if(n / 2 == 0){
                let _zx = _z *x;
                assert!(x != 0, 1);
                let _zxRound = _zx + half;
                _z = _zxRound/ base;
            }; 
            n = n / 2;
            if (n == 0)
                break;
        };
        _z
    }
    public fun pow(a: u256, x: u256): u256 {
        let ans = 1u256;
        let base = a;
        while (x > 0) {
            if (x % 2 == 1) {
                ans = ans * base;
            };
            base = base * base;
            x = x / 2;
        };
        return ans
    }
    
    public fun secure_sub(x: u256, y: u256): u256{
        if (y > x ) return 0;
        return (x - y)
    }
    
    #[view]
    public fun max_u256(a : u256,b : u256): u256{
        if(a < b)
            return b
        else    
            return a
    }
}
