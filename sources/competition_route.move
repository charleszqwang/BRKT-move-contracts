/// This module likely handles the routing logic for different types of competitions, 
/// directing operations to the appropriate competition modules.
module brkt_addr::competition_route {
    use brkt_addr::paid_predictable_competition;
    use brkt_addr::predictable_competition;
    use brkt_addr::competition_factory;
    use brkt_addr::competition;
    use aptos_framework::coin;
    use std::string::String;
    use std::signer;
    
    // Errors
    const EUNSUPPORTED_COMPETITION_TYPE: u64 = 400;

    struct CompetitionRoute has key, drop, store {
        competition_factory_address: address,
    }

    // Entry functions

    /*
     * Creates a new CompetitionRoute instance.
     *
     * @param brkt_signer - The signer of the transaction.
     * @param competition_factory_address - The address of the competition factory.
     */
    entry fun new(brkt_signer: &signer, competition_factory_address: address) {
        move_to(brkt_signer, CompetitionRoute { competition_factory_address });
    }

    /*
     * Creates a bracket prediction for a competition route.
     *
     * @param sender - The signer creating the bracket prediction.
     * @param route_owner_address - The address of the route owner.
     * @param competition_id - The ID of the competition.
     * @param match_predictions - The vector of match predictions.
     */
    public entry fun create_bracket_prediction<CoinType>(
        sender: &signer,
        route_owner_address:address, 
        competition_id : String, 
        match_predictions: vector<u8>
    ) acquires CompetitionRoute {
        let competition_factory_address = borrow_global<CompetitionRoute>(route_owner_address)
            .competition_factory_address;

        let competition_type = competition_factory::get_competition_implType(competition_factory_address, competition_id);
        let competition_owner_address = competition_factory::get_competition_address(competition_factory_address, competition_id);

        if(competition_type == competition_factory::get_predictable()) {
            predictable_competition::create_bracket_prediction(
                sender, 
                competition_owner_address, 
                competition_id, 
                signer::address_of(sender),
                match_predictions
            );
        } else if(competition_type == competition_factory::get_paid_predictable()) {
            let fee = paid_predictable_competition::get_fee(competition_owner_address, &competition_id);
            let has_user_registered = paid_predictable_competition::has_user_registered(
                competition_owner_address, 
                competition_id, 
                signer::address_of(sender)
            );
            if (fee > 0 && !has_user_registered) {
                let pool_addr = paid_predictable_competition::get_pool_addr(competition_owner_address, &competition_id);
                coin::transfer<CoinType>(sender, pool_addr, (fee as u64));
            };

            paid_predictable_competition::create_bracket_prediction<CoinType>(
                sender, 
                competition_owner_address, 
                competition_id, 
                signer::address_of(sender),
                match_predictions
            );
        } else {
            abort EUNSUPPORTED_COMPETITION_TYPE
        };
    }

    // View functions
    
    /*
     * Retrieves the team names for a given competition route.
     *
     * @param route_owner_address - The address of the route owner.
     * @param competition_id - The ID of the competition.
     * @return A vector of strings containing the team names.
     */
    #[view]
    public fun get_team_names(route_owner_address:address, competition_id : String) : vector<String> acquires CompetitionRoute {
        let competition_factory_address = borrow_global<CompetitionRoute>(route_owner_address)
            .competition_factory_address;

        let competition_type = competition_factory::get_competition_implType(competition_factory_address, competition_id);
        let competition_owner_address = competition_factory::get_competition_address(competition_factory_address, competition_id);

        if(competition_type == competition_factory::get_base()) {
            return competition::get_team_names(competition_owner_address, competition_id)
        } else if(competition_type == competition_factory::get_predictable()) {
            return predictable_competition::get_team_names(competition_owner_address, competition_id)
        } else if(competition_type == competition_factory::get_paid_predictable()) {
            return paid_predictable_competition::get_team_names(competition_owner_address, competition_id)
        };

        vector[]
    }
}