module nippy_pool::loan_kernel_logic {
	use std::signer;
    use std::vector;
    use std::bcs;
    use std::aptos_hash;
    use aptos_std::from_bcs;
    use std::debug::print;
    use aptos_std::smart_table::{Self, SmartTable};

    public fun loan_agreement_ids(debtors: vector<address>, terms_params: vector<u256>, salts: vector<u256>): vector<u256>{
        let length = vector::length(&salts);
        assert!(vector::length(&debtors) >= length, 32);
        assert!(vector::length(&terms_params) >= length, 32);
        let ids = vector::empty<u256>();
        let i = 0u64;
        while (i < length) {
            let raw: vector<u8> = bcs::to_bytes<address>(vector::borrow(&debtors,i));
            vector::append(&mut raw, bcs::to_bytes<u256>(vector::borrow(&terms_params,i)));
            vector::append(&mut raw, bcs::to_bytes<u256>(vector::borrow(&salts,i)));
            let raw_id: vector<u8> = aptos_hash::blake2b_256(raw);
            vector::push_back(&mut ids, from_bcs::to_u256(raw_id));   
        };
        return ids
    }
}