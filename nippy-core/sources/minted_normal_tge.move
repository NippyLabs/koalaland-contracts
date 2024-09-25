module nippy_pool::minted_normal_tge {
    // use std::vector;
	use std::signer;
    // use std::debug::print;
    // use aptos_std::smart_table::{Self, SmartTable};

    const ENOT_OWNER: u64 = 1;
    public fun only_issuer(account: &signer) {
        assert!(signer::address_of(account) == @issuer, ENOT_OWNER)
    }

}