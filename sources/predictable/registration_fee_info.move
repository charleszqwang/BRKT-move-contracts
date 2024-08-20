/// This module manages information related to registration fees for competitions, 
/// including the handling of fee payments and validations.
module brkt_addr::registration_fee_info {
    // Definitions
    struct RegistrationFeeInfo has store, copy {
        fee: u256,
    }

    /*
     * Creates a new RegistrationFeeInfo instance.
     *
     * @param fee - The registration fee.
     * @return A new RegistrationFeeInfo instance.
     */
    public fun new(fee: u256): RegistrationFeeInfo {
        RegistrationFeeInfo {
            fee,
        }
    }

    /*
     * Retrieves the fee from the given RegistrationFeeInfo struct.
     *
     * @param info - The RegistrationFeeInfo struct containing the fee information.
     * @return The fee value.
     */
    public fun get_fee(info: &RegistrationFeeInfo): u256 {
        info.fee
    }
}