/// This module manages the state of paid predictable competitions. 
/// It includes definitions for the PaidPredictableCompetitionState struct, 
/// which holds information such as total registration reserves, registration fee info, 
/// claimed rewards, and the predictable competition state. It also provides functions to
/// create new instances, get and set various state properties, and manage rewards.
module brkt_addr::paid_predictable_competition_state {
    // Dependencies
    use brkt_addr::predictable_competition_state::PredictableCompetitionState;
    use brkt_addr::registration_fee_info::{RegistrationFeeInfo, Self};
    use std::simple_map::{SimpleMap, Self};
    use aptos_framework::account;

    // Definitions
    struct PaidPredictableCompetitionState has store {
        total_registration_reserves: u256,
        registration_fee_info: RegistrationFeeInfo,
        claimed_rewards: SimpleMap<address, bool>,
        predict_competition_state: PredictableCompetitionState,
        pool_addr: address,
        pool_signer_cap: account::SignerCapability,
    }

    // Public functions

    /*
     * Creates a new instance of PaidPredictableCompetitionState.
     *
     * @param total_registration_reserves - The total registration reserves.
     * @param registration_fee_info - The registration fee information.
     * @param claimed_rewards - The claimed rewards.
     * @param predict_competition - The predictable competition state.
     * @param pool_addr - The pool address.
     * @param pool_signer_cap - The pool signer capability.
     * @return PaidPredictableCompetitionState - The new instance of PaidPredictableCompetitionState.
     */
    public fun new(
        total_registration_reserves: u256,
        registration_fee_info: RegistrationFeeInfo,
        claimed_rewards: SimpleMap<address, bool>,
        predict_competition: PredictableCompetitionState,
        pool_addr: address,
        pool_signer_cap: account::SignerCapability,
    ): PaidPredictableCompetitionState {
        PaidPredictableCompetitionState {
            total_registration_reserves: total_registration_reserves,
            registration_fee_info: registration_fee_info,
            claimed_rewards: claimed_rewards,
            predict_competition_state: predict_competition,
            pool_addr,
            pool_signer_cap,
        }
    }

    // Getters and Setters

    public fun get_predict_competition_state(state: &PaidPredictableCompetitionState): &PredictableCompetitionState {
        &state.predict_competition_state
    }

    public fun get_predict_competition_state_as_mut(state: &mut PaidPredictableCompetitionState): &mut PredictableCompetitionState {
        &mut state.predict_competition_state
    }

    public fun get_registration_fee(state: &PaidPredictableCompetitionState): u256 {
        registration_fee_info::get_fee(&state.registration_fee_info)
    }

    public fun get_registration_fee_info(state: &PaidPredictableCompetitionState): &RegistrationFeeInfo {
        &state.registration_fee_info
    }

    public fun get_total_registration_reserves(state: &PaidPredictableCompetitionState): u256 {
        state.total_registration_reserves
    }

    public fun set_total_registration_reserves(state: &mut PaidPredictableCompetitionState, total_registration_reserves: u256) {
        state.total_registration_reserves = total_registration_reserves;
    }

    public fun did_claim_rewards(state: &PaidPredictableCompetitionState, user: address): bool {
        *simple_map::borrow(&state.claimed_rewards, &user)
    }

    public fun set_claim_rewards(state: &mut PaidPredictableCompetitionState, user: address, value: bool) {
        simple_map::upsert(&mut state.claimed_rewards, user, value);
    }

    public fun get_pool_addr(state: &PaidPredictableCompetitionState): address {
        state.pool_addr
    }
    
    public fun get_pool_signer_cap(state: &PaidPredictableCompetitionState): &account::SignerCapability {
        &state.pool_signer_cap
    }
}