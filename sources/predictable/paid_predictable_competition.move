/// This module manages competitions that require a registration fee and handle rewards. 
/// It integrates payment logic with the competition management, 
/// ensuring that only paid participants can join and that rewards are distributed correctly.
module brkt_addr::paid_predictable_competition {
    // Dependencies
    use brkt_addr::paid_predictable_competition_state::{PaidPredictableCompetitionState, Self};
    use brkt_addr::predictable_competition_state::{PredictableCompetitionState, Self};
    use brkt_addr::registration_fee_info::{Self, RegistrationFeeInfo};
    use brkt_addr::competition_state::{CompetitionState, Self};
    use brkt_addr::match_outcome::MatchOutcome;
    use brkt_addr::predictable_competition;
    use brkt_addr::competition;
    use aptos_framework::coin;
    use std::simple_map::{SimpleMap, Self};
    use std::string::{Self, String, utf8};
    use std::option::{Self, Option};
    use std::account;
    use std::signer;
    use std::vector;
    use std::event;

    // Errors
    const EINVALID_EXPIRATION: u64 = 301;
    const EINCORRECT_REGISTRATION_FEE_PAID: u64 = 302;
    const ENO_REGISTRATION_FEE: u64 = 303;
    const EUSER_NOT_REGISTERED: u64 = 304;
    const ENO_PENDING_REWARDS: u64 = 305;

    // Definitions
    friend brkt_addr::competition_factory;

    struct PaidPredictableCompetitions has key, store {
        competitions: SimpleMap<String, PaidPredictableCompetitionState>,
    }

    #[event]
    struct UserPaidForBracketPrediction has drop, store {
        user: address,
        fee_info: u256,
    }

    #[event]
    struct UserRefundedForBracket has drop, store {
        user: address,
        amount: u256,
    }

    #[event]
    struct UserClaimedRewards has drop, store {
        user: address,
        amount: u256,
    }

    // Entry functions

    /*
     * Initializes a PaidPredictableCompetitions contract.
     *
     * @param competition_owner - The address of the competition owner.
     * @param competition_id - The ID of the competition.
     * @param competition_name - The name of the competition.
     * @param num_teams - The number of teams in the competition.
     * @param starting_epoch - The starting epoch of the competition.
     * @param expiration_epoch - The expiration epoch of the competition.
     * @param team_names - The names of the teams in the competition.
     * @param banner_URI - The URI of the competition banner.
     * @param total_points_per_round - The total points per round in the competition.
     * @param registration_fee - The registration fee for the competition.
     */
    public entry fun initialize<CoinType>(
        competition_owner: &signer,
        competition_id: String,
        competition_name: String,
        num_teams: u16,
        starting_epoch: u64,
        expiration_epoch: u64,
        team_names: vector<String>,
        banner_URI: Option<String>,
        total_points_per_round: u16,
        registration_fee: u256,
    ) acquires PaidPredictableCompetitions {
        // Get the banner URI
        let banner = *option::borrow_with_default(&banner_URI, &utf8(b""));
        
        // Initialize the predictable competition state
        let predictable_competition_state = predictable_competition::initialize_predictable_competition_state(
            competition_name,
            num_teams,
            starting_epoch,
            expiration_epoch,
            team_names,
            banner,
            total_points_per_round
        );

        assert!(expiration_epoch != 0, EINVALID_EXPIRATION);

        // Create a pool account
        let competition_id_bytes = string::bytes(&competition_id);
        let (pool, pool_signer_cap) = account::create_resource_account(competition_owner, *competition_id_bytes);
        let pool_addr = signer::address_of(&pool);
        coin::register<CoinType>(&pool);

        // Create a new PaidPredictableCompetitionState
        let total_reg_reserves: u256 = 0;
        let claimed_rewards = simple_map::new<address, bool>();
        let registration_fee_info = registration_fee_info::new(registration_fee);
        let paid_predictable_competition_state = paid_predictable_competition_state::new(
            total_reg_reserves,
            registration_fee_info,
            claimed_rewards,
            predictable_competition_state,
            pool_addr,
            pool_signer_cap
        );

        // Add the PaidPredictableCompetitionState to the PaidPredictableCompetitions
        if (exists<(PaidPredictableCompetitions)>(signer::address_of(competition_owner))) {
            let paid_predictable_competitions = borrow_global_mut<PaidPredictableCompetitions>(signer::address_of(competition_owner));
            simple_map::add(&mut paid_predictable_competitions.competitions, competition_id, paid_predictable_competition_state);
        } else {
            let paid_predictable_competitions = PaidPredictableCompetitions {
                competitions: simple_map::new<String, PaidPredictableCompetitionState>(),
                // owner: resource_account::retrieve_resource_account_cap(competition_owner, signer::address_of(competition_owner)),
            };
            simple_map::add(&mut paid_predictable_competitions.competitions, competition_id, paid_predictable_competition_state);
            move_to(competition_owner, paid_predictable_competitions);
        };
    }

    /*
     * Creates a bracket prediction for a paid predictable competition.
     *
     * @param sender - The signer of the transaction.
     * @param owner_address - The address of the competition owner.
     * @param competition_id - The ID of the competition.
     * @param registrant - The address of the registrant.
     * @param match_predictions - The vector of match predictions.
     */
    public entry fun create_bracket_prediction<CoinType>(
            sender: &signer, 
            owner_address: address,
            competition_id: String, 
            registrant: address, 
            match_predictions: vector<u8>
        ) acquires PaidPredictableCompetitions {
        // Get the PaidPredictableCompetitionState
        let paid_competitions = borrow_global_mut<PaidPredictableCompetitions>(owner_address);
        let paid_competition_state = get_paid_competition_state_as_mut(paid_competitions, &competition_id);
        let predict_competition_state = paid_predictable_competition_state::get_predict_competition_state(paid_competition_state);
        let pool_addr = paid_predictable_competition_state::get_pool_addr(paid_competition_state);
        let comp_state = predictable_competition_state::get_competition(predict_competition_state);
        competition::when_not_live(comp_state);

        // Check if the user has already registered
        let fee = paid_predictable_competition_state::get_registration_fee(paid_competition_state);
        if (fee != 0) {
            let registered_users = predictable_competition_state::get_registered_users(predict_competition_state);
            let total_registration_reserves = paid_predictable_competition_state::get_total_registration_reserves(paid_competition_state);
            let balance = (coin::balance<CoinType>(pool_addr) as u256);
            if (vector::contains(registered_users, &registrant)) {
                assert!(balance == total_registration_reserves, EINCORRECT_REGISTRATION_FEE_PAID);
            } else {
                assert!(balance == total_registration_reserves + fee, EINCORRECT_REGISTRATION_FEE_PAID);
                let new_total = total_registration_reserves + fee;
                paid_predictable_competition_state::set_total_registration_reserves(paid_competition_state, new_total);

                // Emit event
                let user_paid_bracket_prediction_event = UserPaidForBracketPrediction{
                    user: registrant,
                    fee_info: fee,
                };
                event::emit(user_paid_bracket_prediction_event);
            };
        };

        // Register the user
        paid_predictable_competition_state::set_claim_rewards(
            paid_competition_state, 
            registrant, 
            false
        );

        // Save the user prediction
        let predict_competition_state_mut = paid_predictable_competition_state::get_predict_competition_state_as_mut(paid_competition_state);
        predictable_competition::save_user_prediction(
            predict_competition_state_mut,
            sender,
            registrant,
            match_predictions,
        );
    }

    /*
     * Claims rewards for a specific competition.
     *
     * @param sender - The address of the sender.
     * @param competition_id - The ID of the competition.
     */
    public entry fun claim_rewards<CoinType>(sender: &signer, owner: address, competition_id: String) acquires PaidPredictableCompetitions {
        let paid_competitions = borrow_global_mut<PaidPredictableCompetitions>(owner);
        let paid_competition_state = simple_map::borrow_mut<String, PaidPredictableCompetitionState>(
            &mut paid_competitions.competitions, 
            &competition_id
        );
        let predict_comp_state = paid_predictable_competition_state::get_predict_competition_state(paid_competition_state);
        let comp_state = predictable_competition_state::get_competition(predict_comp_state);
        competition::when_completed(comp_state);
        let pending_rewards = p_calculate_pending_rewards(
            signer::address_of(sender), 
            paid_competition_state, 
            predict_comp_state, 
            comp_state
        );

        assert!(pending_rewards != 0, ENO_PENDING_REWARDS);

        paid_predictable_competition_state::set_claim_rewards(paid_competition_state, signer::address_of(sender), true);

        let pool_signer_cap = paid_predictable_competition_state::get_pool_signer_cap(paid_competition_state);
        let pool_signer = account::create_signer_with_capability(pool_signer_cap);
        coin::transfer<CoinType>(&pool_signer, signer::address_of(sender), (pending_rewards as u64));

        // Emit event
        let user_claimed_rewards = UserClaimedRewards {
            user: signer::address_of(sender),
            amount: pending_rewards,
        };
        event::emit(user_claimed_rewards);
    }

    /*
     * Starts a paid predictable competition.
     *
     * @param sender - The signer initiating the transaction.
     * @param competition_id - The ID of the competition to start.
     * @return None.
     */
    public entry fun start(sender: &signer, competition_id: String) acquires PaidPredictableCompetitions {
        let paid_competitions = borrow_global_mut<PaidPredictableCompetitions>(signer::address_of(sender));
        let paid_competition = get_paid_competition_state_as_mut(paid_competitions, &competition_id);
        let predict_comp_state = paid_predictable_competition_state::get_predict_competition_state_as_mut(paid_competition);
        let competition_state = predictable_competition_state::get_competition_state_as_mut(predict_comp_state);
        competition::start_competition(competition_state);
    }

    /*
     * Sets the team names for a specific competition.
     *
     * @param sender - The address of the sender.
     * @param competition_id - The ID of the competition.
     * @param names - A vector of team names.
     */
    public entry fun set_team_names (
        sender: &signer, 
        competition_id: String, 
        names: vector<String>
    ) acquires PaidPredictableCompetitions {
        let paid_competitions = borrow_global_mut<PaidPredictableCompetitions>(signer::address_of(sender));
        let paid_competition = get_paid_competition_state_as_mut(paid_competitions, &competition_id);
        let predict_comp_state = paid_predictable_competition_state::get_predict_competition_state_as_mut(paid_competition);
        let competition_state = predictable_competition_state::get_competition_state_as_mut(predict_comp_state);
        competition::set_team_name_for_competition(competition_state, &names);
    }

    /*
     * Completes a match for a paid predictable competition.
     *
     * @param sender - The signer of the transaction.
     * @param competition_id - The ID of the competition.
     * @param match_id - The ID of the match.
     * @param winning_id - The ID of the winning participant.
     * @return None.
     */
    public entry fun complete_match(
        sender: &signer, 
        competition_id: String, 
        match_id: u256, 
        winning_id: u8
    ) acquires PaidPredictableCompetitions {
        let paid_competitions = borrow_global_mut<PaidPredictableCompetitions>(signer::address_of(sender));
        let paid_competition = get_paid_competition_state_as_mut(paid_competitions, &competition_id);
        let predict_comp_state = paid_predictable_competition_state::get_predict_competition_state_as_mut(paid_competition);
        let competition_state = predictable_competition_state::get_competition_state_as_mut(predict_comp_state);

        competition::complete_match_for_competition(competition_state, match_id, winning_id);
    }

    /*
     * Advances the round of a paid predictable competition.
     *
     * @param sender - The signer of the transaction.
     * @param competition_id - The ID of the competition to advance the round.
     * @return None.
     */
    public entry fun advance_round(
            sender: &signer, 
            competition_id: String
        ) acquires PaidPredictableCompetitions {
        let paid_competitions = borrow_global_mut<PaidPredictableCompetitions>(signer::address_of(sender));
        let paid_competition = get_paid_competition_state_as_mut(paid_competitions, &competition_id);
        let predict_comp_state = paid_predictable_competition_state::get_predict_competition_state_as_mut(paid_competition);
        let competition_state = predictable_competition_state::get_competition_state_as_mut(predict_comp_state);

        competition::p_advance_round(competition_state);      
    }

    /*
     * Advances the round of a paid predictable competition with the given match results.
     *
     * @param sender - The signer of the transaction.
     * @param competition_id - The ID of the competition.
     * @param match_results - The vector of match results.
     * @return None.
     */
    public entry fun advance_round_with_results (
        sender: &signer, 
        competition_id: String, 
        match_results: vector<u8>
    ) acquires PaidPredictableCompetitions {
        let paid_competitions = borrow_global_mut<PaidPredictableCompetitions>(signer::address_of(sender));
        let paid_competition = get_paid_competition_state_as_mut(paid_competitions, &competition_id);
        let predict_comp_state = paid_predictable_competition_state::get_predict_competition_state_as_mut(paid_competition);
        let competition_state = predictable_competition_state::get_competition_state_as_mut(predict_comp_state);

        competition::p_advance_round_with_results(competition_state, match_results);
    }

    // Public functions

    /*
     * Refunds the registration fee for a specific competition.
     *
     * @param sender - The signer who is requesting the refund.
     * @param competition_id - The ID of the competition.
     */
    public entry fun refund_registration_fee<CoinType>(
        sender: &signer, 
        owner_address: address,
        competition_id: String
    ) acquires PaidPredictableCompetitions {
        // Get the PaidPredictableCompetitionState
        let paid_competitions = borrow_global_mut<PaidPredictableCompetitions>(owner_address);
        let paid_competition_state = simple_map::borrow_mut<String, PaidPredictableCompetitionState>(
            &mut paid_competitions.competitions, 
            &competition_id
        );

        // Refund the registration fee
        let fee = paid_predictable_competition_state::get_registration_fee(paid_competition_state);
        let predict_comp_state = paid_predictable_competition_state::get_predict_competition_state_as_mut(paid_competition_state);
        let comp_state = predictable_competition_state::get_competition(predict_comp_state);

        // Check if the competition has expired
        assert!(fee != 0, ENO_REGISTRATION_FEE);
        competition::when_expired(comp_state);

        // Check if the user is registered
        let registered_users = predictable_competition_state::get_registered_users_as_mut(predict_comp_state);
        let (isExist, index) = vector::index_of(registered_users, &signer::address_of(sender));
        assert!(isExist, EUSER_NOT_REGISTERED);

        // Refund the registration fee
        vector::swap_remove<address>(registered_users, index);
        let pool_signer_cap = paid_predictable_competition_state::get_pool_signer_cap(paid_competition_state);
        let pool_signer = account::create_signer_with_capability(pool_signer_cap);
        coin::transfer<CoinType>(&pool_signer, signer::address_of(sender), (fee as u64));
        let total_registration_reserves = paid_predictable_competition_state::get_total_registration_reserves(paid_competition_state);
        let new_total = total_registration_reserves - fee;
        paid_predictable_competition_state::set_total_registration_reserves(paid_competition_state, new_total);

        // Emit evnet
        let user_refunded_for_bracket = UserRefundedForBracket{
            user: signer::address_of(sender),
            amount: fee,
        };
        event::emit(user_refunded_for_bracket);
    }  

    /*
     * Retrieves the registration fee for a specific competition.
     *
     * @param owner_address - The address of the owner of the competitions.
     * @param competition_id - The ID of the competition.
     * @return The registration fee for the specified competition.
     */
    public fun get_fee(owner_address: address, competition_id: &String) : u256 acquires PaidPredictableCompetitions {
        let paid_competitions = borrow_global<PaidPredictableCompetitions>(owner_address);
        
        let comp_state = simple_map::borrow<String, PaidPredictableCompetitionState>(
            &paid_competitions.competitions, 
            competition_id,
        );

        return paid_predictable_competition_state::get_registration_fee(comp_state)
    }

    /*
     * Retrieves the address of a pool for a given owner and competition ID.
     *
     * @param owner_address - The address of the owner.
     * @param competition_id - The ID of the competition.
     * @return address - The address of the pool.
     */
    public fun get_pool_addr(owner_address: address, competition_id: &String) : address acquires PaidPredictableCompetitions {
        let paid_competitions = borrow_global<PaidPredictableCompetitions>(owner_address);
        
        let comp_state = simple_map::borrow<String, PaidPredictableCompetitionState>(
            &paid_competitions.competitions, 
            competition_id,
        );

        return paid_predictable_competition_state::get_pool_addr(comp_state)
    }

    // View functions

    /*
     * Retrieves the match outcome for a specific match in a paid predictable competition.
     *
     * @param owner_address - The address of the owner of the paid predictable competitions.
     * @param competition_id - The ID of the competition.
     * @param match_id - The ID of the match.
     * @return MatchOutcome - The outcome of the match.
     */
    #[view]
    public fun get_match_outcome(
        owner_address: address, 
        competition_id: String, 
        match_id: u256
    ) : MatchOutcome acquires PaidPredictableCompetitions {
        let paid_competitions = borrow_global<PaidPredictableCompetitions>(owner_address);
        let paid_competition_state = get_paid_competition_state(paid_competitions, &competition_id);
        let predict_competition_state = paid_predictable_competition_state::get_predict_competition_state(paid_competition_state);
        let competition_state = predictable_competition_state::get_competition(predict_competition_state);
        return competition::f_get_match_outcome(competition_state, match_id)
    }

    /*
     * Retrieves the progression of a paid predictable competition.
     *
     * @param owner_address - The address of the competition owner.
     * @param competition_id - The ID of the competition.
     * @return vector<MatchOutcome> - The progression of the competition bracket.
     */
    #[view]
    public fun get_competition_progression(
        owner_address: address, 
        competition_id: String
    ) : vector<MatchOutcome> acquires PaidPredictableCompetitions {
        let paid_competitions = borrow_global<PaidPredictableCompetitions>(owner_address);
        let paid_competition_state = get_paid_competition_state(paid_competitions, &competition_id);
        let predict_competition_state = paid_predictable_competition_state::get_predict_competition_state(paid_competition_state);
        let competition_state = predictable_competition_state::get_competition(predict_competition_state);
        return competition_state::get_bracket_progression(competition_state)
    }

    /*
     * Checks if a paid predictable competition has started.
     *
     * @param owner_address - The address of the owner of the competition.
     * @param competition_id - The ID of the competition.
     * @return bool - Returns true if the competition has started, false otherwise.
     */
    #[view]
    public fun has_started(owner_address: address, competition_id: String): bool acquires PaidPredictableCompetitions {
        let paid_competitions = borrow_global<PaidPredictableCompetitions>(owner_address);
        let paid_competition = get_paid_competition_state(paid_competitions, &competition_id);
        let predict_comp_state = paid_predictable_competition_state::get_predict_competition_state(paid_competition);
        let competition_state = predictable_competition_state::get_competition(predict_comp_state);
        
        competition::p_has_started(competition_state)
    }

    /*
     * Retrieves the team names for a specific competition.
     *
     * @param owner_address - The address of the owner of the competition.
     * @param competition_id - The ID of the competition.
     * @return A vector of strings containing the team names.
     */
    #[view]
    public fun get_team_names(owner_address: address, competition_id: String): vector<String> acquires PaidPredictableCompetitions {
        let paid_competitions = borrow_global<PaidPredictableCompetitions>(owner_address);
        let paid_competition = get_paid_competition_state(paid_competitions, &competition_id);
        let predict_comp_state = paid_predictable_competition_state::get_predict_competition_state(paid_competition);
        let competition_state = predictable_competition_state::get_competition(predict_comp_state);
        
        competition::p_get_team_names(competition_state)
    }

    /*
     * Checks if a user has registered for a specific competition.
     *
     * @param sender - The address of the sender.
     * @param competition_id - The ID of the competition.
     * @param user - The address of the user to check registration for.
     * @return bool - Returns true if the user has registered for the competition, false otherwise.
     */
    #[view]
    public fun has_user_registered(
        sender: address,
        competition_id: String,
        user: address
    ): bool acquires PaidPredictableCompetitions {
        let paid_competitions = borrow_global<PaidPredictableCompetitions>(sender);
        let paid_competition = get_paid_competition_state(paid_competitions, &competition_id);
        let predict_comp_state = paid_predictable_competition_state::get_predict_competition_state(paid_competition);

        return p_has_user_registered(user, predict_comp_state)
    }

    /*
     * Retrieves the bracket prediction of a user for a specific competition.
     *
     * @param sender - The address of the sender.
     * @param competition_id - The ID of the competition.
     * @param user - The address of the user.
     * @return The bracket prediction of the user as a vector of u8.
     */
    #[view]
    public fun get_user_bracket_prediction(
        sender: address, 
        competition_id: String, 
        user: address
    ): vector<u8> acquires PaidPredictableCompetitions {
        let paid_competitions = borrow_global<PaidPredictableCompetitions>(sender);
        let paid_competition = get_paid_competition_state(paid_competitions, &competition_id);
        let predict_comp_state = paid_predictable_competition_state::get_predict_competition_state(paid_competition);
        let user_bracket_predictions = predictable_competition_state::get_user_bracket_predictions(predict_comp_state);
        
        if(simple_map::contains_key(&user_bracket_predictions, &user)) { 
            return *simple_map::borrow(&user_bracket_predictions, &user)
        };

        vector::empty<u8>()
    }

    /*
     * Calculates the total score for a given competition.
     *
     * @param sender - The address of the sender.
     * @param competition_id - The ID of the competition.
     * @return The total score for the competition.
     */
    #[view]
    public fun get_total_score(
        sender: address, 
        competition_id: String, 
    ): u256 acquires PaidPredictableCompetitions {
        let paid_competitions = borrow_global<PaidPredictableCompetitions>(sender);
        let paid_competition = get_paid_competition_state(paid_competitions, &competition_id);
        let predict_comp_state = paid_predictable_competition_state::get_predict_competition_state(paid_competition);
        
        return predictable_competition::f_get_total_score(predict_comp_state)
    }

    /*
     * Calculates the user's score percentage in a paid predictable competition.
     *
     * @param competition_owner - The address of the competition owner.
     * @param sender - The address of the user.
     * @param competition_id - The ID of the competition.
     * @return The user's score percentage.
     */
    #[view]
    public fun get_user_score_percent(
        competition_owner: address,
        sender: address, 
        competition_id: String, 
    ): u256 acquires PaidPredictableCompetitions {
        let paid_competitions = borrow_global<PaidPredictableCompetitions>(competition_owner);
        let paid_competition = get_paid_competition_state(paid_competitions, &competition_id);
        let predict_comp_state = paid_predictable_competition_state::get_predict_competition_state(paid_competition);
        
        if (!p_has_user_registered(sender, predict_comp_state)) {
            return 0
        };
        
        return predictable_competition::f_get_user_score_percent(predict_comp_state, sender)
    }

    /*
     * Retrieves the bracket score of a user in a paid predictable competition.
     *
     * @param sender - The address of the sender.
     * @param competition_id - The ID of the competition.
     * @param user - The address of the user.
     * @return The bracket score of the user.
     */
    #[view]
    public fun get_user_bracket_score(
        sender: address, 
        competition_id: String, 
        user: address,
    ): u256 acquires PaidPredictableCompetitions {
        let paid_competitions = borrow_global<PaidPredictableCompetitions>(sender);
        let paid_competition = get_paid_competition_state(paid_competitions, &competition_id);
        let predict_comp_state = paid_predictable_competition_state::get_predict_competition_state(paid_competition);
        
        if (!p_has_user_registered(user, predict_comp_state)) {
            return 0
        };
        
        return predictable_competition::f_get_user_bracket_score(predict_comp_state, user)
    }

    /*
     * Calculates the pending rewards for a user in a paid predictable competition.
     *
     * @param competition_owner - The address of the competition owner.
     * @param user_addr - The address of the user.
     * @param competition_id - The ID of the competition.
     * @return The amount of pending rewards for the user.
     */
    #[view]
    public fun calculate_pending_rewards(
            competition_owner: address,
            user_addr: address, 
            competition_id: String
        ): u256 acquires PaidPredictableCompetitions {
        let paid_competitions = borrow_global<PaidPredictableCompetitions>(competition_owner);
        let paid_competition_state = get_paid_competition_state(paid_competitions, &competition_id);
        let predict_comp_state = paid_predictable_competition_state::get_predict_competition_state(paid_competition_state);
        let comp_state = predictable_competition_state::get_competition(predict_comp_state);
        p_calculate_pending_rewards(user_addr, paid_competition_state, predict_comp_state, comp_state)
    }

    #[view]
    public fun get_bracket_prediction_fee_info(
        owner_address: address, 
        competition_id: String
    ): RegistrationFeeInfo acquires PaidPredictableCompetitions {
        let paid_competitions = borrow_global<PaidPredictableCompetitions>(owner_address);
        let paid_competition_state = get_paid_competition_state(paid_competitions, &competition_id);
        *paid_predictable_competition_state::get_registration_fee_info(paid_competition_state)
    }

    // Private functions

    /*
     * Checks if a user has registered for a predictable competition.
     *
     * @param sender - The address of the user.
     * @param predict_comp_state - The state of the predictable competition.
     * @return true if the user has registered, false otherwise.
     */
    fun p_has_user_registered(
        sender: address,
        predict_comp_state: &PredictableCompetitionState,
    ): bool {
        let registered_users = predictable_competition_state::get_registered_users(predict_comp_state);
        let len = vector::length(registered_users);
        let i = 0;
        while (i < len) {
            if (vector::borrow(registered_users, i) == &sender) {
                return true
            };
            i = i + 1
        };
        false
    }

    /*
     * Calculates the pending rewards for a given address in the paid predictable competition.
     *
     * @param addr - The address for which to calculate the pending rewards.
     * @param paid_competition_state - The state of the paid predictable competition.
     * @param predict_comp_state - The state of the predictable competition.
     * @param comp_state - The state of the competition.
     * @return The amount of pending rewards for the given address.
     */
    fun p_calculate_pending_rewards(
            addr: address, 
            paid_competition_state: &PaidPredictableCompetitionState, 
            predict_comp_state: &PredictableCompetitionState,
            comp_state: &CompetitionState,
        ): u256 {
        // Check if the user has claimed rewards
        let did_claim_rewards = paid_predictable_competition_state::did_claim_rewards(paid_competition_state, addr);
        let has_finished = competition_state::get_has_finished(comp_state);

        // Calculate the pending rewards
        if (!did_claim_rewards && has_finished) {
            let percent_of_total = predictable_competition::f_get_user_score_percent(
                predict_comp_state,
                addr,
            );
            let total_registration_reserves = paid_predictable_competition_state::get_total_registration_reserves(
                paid_competition_state
            );
            return total_registration_reserves * percent_of_total / 10000
        };
        return 0
    }

    /*
     * Retrieves the state of a paid predictable competition.
     *
     * @param paid_competitions - The collection of paid predictable competitions.
     * @param competition_id - The ID of the competition to retrieve the state for.
     * @return The state of the specified paid predictable competition.
     */
    fun get_paid_competition_state(
        paid_competitions: &PaidPredictableCompetitions, 
        competition_id: &String
    ): &PaidPredictableCompetitionState {
        simple_map::borrow<String, PaidPredictableCompetitionState>(
            &paid_competitions.competitions, 
            competition_id
        )
    }

    /*
     * Retrieves the mutable reference to the state of a paid predictable competition.
     *
     * @param paid_competitions - A mutable reference to the PaidPredictableCompetitions struct.
     * @param competition_id - The ID of the competition to retrieve the state for.
     * @return A mutable reference to the PaidPredictableCompetitionState struct.
     */
    fun get_paid_competition_state_as_mut(
        paid_competitions: &mut PaidPredictableCompetitions, 
        competition_id: &String
    ): &mut PaidPredictableCompetitionState {
        simple_map::borrow_mut<String, PaidPredictableCompetitionState>(
            &mut paid_competitions.competitions, 
            competition_id
        )
    }
}