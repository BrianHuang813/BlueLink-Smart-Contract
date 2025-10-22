#[test_only]
module blue_link::blue_link_tests {
    use sui::test_scenario::{Self as ts, Scenario};
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use sui::test_utils;
    use blue_link::blue_link::{Self, BondProject, BondToken};
    use std::string;

    // Test addresses
    const ISSUER: address = @0xA;
    const INVESTOR1: address = @0xB;
    const INVESTOR2: address = @0xC;
    const RANDOM_USER: address = @0xD;

    // Test constants
    const TOTAL_SUPPLY: u64 = 100;
    const TOKEN_PRICE: u64 = 1000000000; // 1 SUI
    const ANNUAL_RATE: u64 = 500; // 5%
    const MATURITY_DATE: u64 = 365; // 365 days from issue

    // Error codes from main module
    const EPurchaseAmountIsZero: u64 = 202;
    const EInsufficientPayment: u64 = 201;
    const EInsufficientTokensAvailable: u64 = 204;
    const ENotBondIssuer: u64 = 300;
    const EBondNotMatured: u64 = 400;

    // Helper function to create a test scenario
    fun setup_test(): Scenario {
        ts::begin(ISSUER)
    }

    // Helper function to create a bond project
    fun create_test_bond_project(scenario: &mut Scenario) {
        ts::next_tx(scenario, ISSUER);
        {
            blue_link::create_bond_project(
                b"Green Energy Bond",
                b"Government",
                b"Bond for renewable energy projects",
                TOTAL_SUPPLY,
                TOKEN_PRICE,
                ANNUAL_RATE,
                MATURITY_DATE,
                ts::ctx(scenario)
            );
        };
    }

    // Test 1: Create bond project successfully
    #[test]
    fun test_create_bond_project_success() {
        let mut scenario = setup_test();
        
        create_test_bond_project(&mut scenario);
        
        // Verify bond project was created and transferred to issuer
        ts::next_tx(&mut scenario, ISSUER);
        {
            let project = ts::take_from_sender<BondProject>(&scenario);
            
            let (bond_name, _description, issuer, total_supply, token_price, 
                 tokens_sold, tokens_redeemed, annual_rate, maturity, 
                 raised_funds, redemption_pool, status) = blue_link::get_bond_project_info(&project);
            
            assert!(bond_name == string::utf8(b"Green Energy Bond"), 0);
            assert!(issuer == ISSUER, 1);
            assert!(total_supply == TOTAL_SUPPLY, 2);
            assert!(token_price == TOKEN_PRICE, 3);
            assert!(tokens_sold == 0, 4);
            assert!(tokens_redeemed == 0, 5);
            assert!(annual_rate == ANNUAL_RATE, 6);
            assert!(maturity == MATURITY_DATE, 7);
            assert!(raised_funds == 0, 8);
            assert!(redemption_pool == 0, 9);
            assert!(status == 0, 10); // BOND_STATUS_FUNDRAISING
            
            ts::return_to_sender(&scenario, project);
        };
        
        ts::end(scenario);
    }

    // Test 2: Buy bond tokens successfully
    #[test]
    fun test_buy_bond_tokens_success() {
        let mut scenario = setup_test();
        
        create_test_bond_project(&mut scenario);
        
        // Investor1 buys 5 tokens
        ts::next_tx(&mut scenario, INVESTOR1);
        {
            let mut project = ts::take_from_address<BondProject>(&scenario, ISSUER);
            let payment = coin::mint_for_testing<SUI>(5 * TOKEN_PRICE, ts::ctx(&mut scenario));
            
            blue_link::buy_bond_tokens(&mut project, 5, payment, ts::ctx(&mut scenario));
            
            // Verify project state
            let (_, _, _, _, _, tokens_sold, _, _, _, raised_funds, _, _) = 
                blue_link::get_bond_project_info(&project);
            assert!(tokens_sold == 5, 0);
            assert!(raised_funds == 5 * TOKEN_PRICE, 1);
            
            ts::return_to_address(ISSUER, project);
        };
        
        // Verify investor received 5 bond tokens
        ts::next_tx(&mut scenario, INVESTOR1);
        {
            let token_ids = ts::ids_for_sender<BondToken>(&scenario);
            assert!(token_ids.length() == 5, 2);
        };
        
        ts::end(scenario);
    }

    // Test 3: Buy multiple tokens by different investors
    #[test]
    fun test_multiple_investors() {
        let mut scenario = setup_test();
        
        create_test_bond_project(&mut scenario);
        
        // Investor1 buys 30 tokens
        ts::next_tx(&mut scenario, INVESTOR1);
        {
            let mut project = ts::take_from_address<BondProject>(&scenario, ISSUER);
            let payment = coin::mint_for_testing<SUI>(30 * TOKEN_PRICE, ts::ctx(&mut scenario));
            blue_link::buy_bond_tokens(&mut project, 30, payment, ts::ctx(&mut scenario));
            ts::return_to_address(ISSUER, project);
        };
        
        // Investor2 buys 20 tokens
        ts::next_tx(&mut scenario, INVESTOR2);
        {
            let mut project = ts::take_from_address<BondProject>(&scenario, ISSUER);
            let payment = coin::mint_for_testing<SUI>(20 * TOKEN_PRICE, ts::ctx(&mut scenario));
            blue_link::buy_bond_tokens(&mut project, 20, payment, ts::ctx(&mut scenario));
            ts::return_to_address(ISSUER, project);
        };
        
        // Verify project state
        ts::next_tx(&mut scenario, ISSUER);
        {
            let project = ts::take_from_sender<BondProject>(&scenario);
            let (_, _, _, _, _, tokens_sold, _, _, _, raised_funds, _, _) = 
                blue_link::get_bond_project_info(&project);
            assert!(tokens_sold == 50, 0);
            assert!(raised_funds == 50 * TOKEN_PRICE, 1);
            ts::return_to_sender(&scenario, project);
        };
        
        ts::end(scenario);
    }

    // Test 4: Fail to buy with insufficient payment
    #[test]
    #[expected_failure(abort_code = EInsufficientPayment)]
    fun test_buy_insufficient_payment() {
        let mut scenario = setup_test();
        
        create_test_bond_project(&mut scenario);
        
        ts::next_tx(&mut scenario, INVESTOR1);
        {
            let mut project = ts::take_from_address<BondProject>(&scenario, ISSUER);
            // Try to buy 5 tokens but only pay for 4
            let payment = coin::mint_for_testing<SUI>(4 * TOKEN_PRICE, ts::ctx(&mut scenario));
            blue_link::buy_bond_tokens(&mut project, 5, payment, ts::ctx(&mut scenario));
            ts::return_to_address(ISSUER, project);
        };
        
        ts::end(scenario);
    }

    // Test 5: Fail to buy more tokens than available
    #[test]
    #[expected_failure(abort_code = EInsufficientTokensAvailable)]
    fun test_buy_exceeds_supply() {
        let mut scenario = setup_test();
        
        create_test_bond_project(&mut scenario);
        
        ts::next_tx(&mut scenario, INVESTOR1);
        {
            let mut project = ts::take_from_address<BondProject>(&scenario, ISSUER);
            // Try to buy more than total supply
            let payment = coin::mint_for_testing<SUI>(150 * TOKEN_PRICE, ts::ctx(&mut scenario));
            blue_link::buy_bond_tokens(&mut project, 150, payment, ts::ctx(&mut scenario));
            ts::return_to_address(ISSUER, project);
        };
        
        ts::end(scenario);
    }

    // Test 6: Fail to buy zero tokens
    #[test]
    #[expected_failure(abort_code = EPurchaseAmountIsZero)]
    fun test_buy_zero_tokens() {
        let mut scenario = setup_test();
        
        create_test_bond_project(&mut scenario);
        
        ts::next_tx(&mut scenario, INVESTOR1);
        {
            let mut project = ts::take_from_address<BondProject>(&scenario, ISSUER);
            let payment = coin::mint_for_testing<SUI>(0, ts::ctx(&mut scenario));
            blue_link::buy_bond_tokens(&mut project, 0, payment, ts::ctx(&mut scenario));
            ts::return_to_address(ISSUER, project);
        };
        
        ts::end(scenario);
    }

    // Test 7: Issuer withdraws raised funds
    #[test]
    fun test_withdraw_raised_funds() {
        let mut scenario = setup_test();
        
        create_test_bond_project(&mut scenario);
        
        // Investor buys tokens
        ts::next_tx(&mut scenario, INVESTOR1);
        {
            let mut project = ts::take_from_address<BondProject>(&scenario, ISSUER);
            let payment = coin::mint_for_testing<SUI>(10 * TOKEN_PRICE, ts::ctx(&mut scenario));
            blue_link::buy_bond_tokens(&mut project, 10, payment, ts::ctx(&mut scenario));
            ts::return_to_address(ISSUER, project);
        };
        
        // Issuer withdraws funds
        ts::next_tx(&mut scenario, ISSUER);
        {
            let mut project = ts::take_from_sender<BondProject>(&scenario);
            blue_link::withdraw_raised_funds(&mut project, 5 * TOKEN_PRICE, ts::ctx(&mut scenario));
            
            let (_, _, _, _, _, _, _, _, _, raised_funds, _, _) = 
                blue_link::get_bond_project_info(&project);
            assert!(raised_funds == 5 * TOKEN_PRICE, 0);
            
            ts::return_to_sender(&scenario, project);
        };
        
        // Verify issuer received the withdrawal
        ts::next_tx(&mut scenario, ISSUER);
        {
            let withdrawn_coin = ts::take_from_sender<Coin<SUI>>(&scenario);
            assert!(coin::value(&withdrawn_coin) == 5 * TOKEN_PRICE, 1);
            test_utils::destroy(withdrawn_coin);
        };
        
        ts::end(scenario);
    }

    // Test 8: Non-issuer cannot withdraw funds
    #[test]
    #[expected_failure(abort_code = ENotBondIssuer)]
    fun test_withdraw_not_issuer() {
        let mut scenario = setup_test();
        
        create_test_bond_project(&mut scenario);
        
        // Investor buys tokens
        ts::next_tx(&mut scenario, INVESTOR1);
        {
            let mut project = ts::take_from_address<BondProject>(&scenario, ISSUER);
            let payment = coin::mint_for_testing<SUI>(10 * TOKEN_PRICE, ts::ctx(&mut scenario));
            blue_link::buy_bond_tokens(&mut project, 10, payment, ts::ctx(&mut scenario));
            ts::return_to_address(ISSUER, project);
        };
        
        // Random user tries to withdraw
        ts::next_tx(&mut scenario, RANDOM_USER);
        {
            let mut project = ts::take_from_address<BondProject>(&scenario, ISSUER);
            blue_link::withdraw_raised_funds(&mut project, TOKEN_PRICE, ts::ctx(&mut scenario));
            ts::return_to_address(ISSUER, project);
        };
        
        ts::end(scenario);
    }

    // Test 9: Deposit redemption funds
    #[test]
    fun test_deposit_redemption_funds() {
        let mut scenario = setup_test();
        
        create_test_bond_project(&mut scenario);
        
        // Issuer deposits redemption funds
        ts::next_tx(&mut scenario, ISSUER);
        {
            let mut project = ts::take_from_sender<BondProject>(&scenario);
            let payment = coin::mint_for_testing<SUI>(150 * TOKEN_PRICE, ts::ctx(&mut scenario));
            blue_link::deposit_redemption_funds(&mut project, payment, ts::ctx(&mut scenario));
            
            let (_, _, _, _, _, _, _, _, _, _, redemption_pool, _) = 
                blue_link::get_bond_project_info(&project);
            assert!(redemption_pool == 150 * TOKEN_PRICE, 0);
            
            ts::return_to_sender(&scenario, project);
        };
        
        ts::end(scenario);
    }

    // Test 10: Non-issuer cannot deposit redemption funds
    #[test]
    #[expected_failure(abort_code = ENotBondIssuer)]
    fun test_deposit_redemption_not_issuer() {
        let mut scenario = setup_test();
        
        create_test_bond_project(&mut scenario);
        
        ts::next_tx(&mut scenario, RANDOM_USER);
        {
            let mut project = ts::take_from_address<BondProject>(&scenario, ISSUER);
            let payment = coin::mint_for_testing<SUI>(TOKEN_PRICE, ts::ctx(&mut scenario));
            blue_link::deposit_redemption_funds(&mut project, payment, ts::ctx(&mut scenario));
            ts::return_to_address(ISSUER, project);
        };
        
        ts::end(scenario);
    }

    // Test 11: Redeem bond token successfully
    #[test]
    fun test_redeem_bond_token_success() {
        let mut scenario = setup_test();
        
        create_test_bond_project(&mut scenario);
        
        // Investor buys tokens
        ts::next_tx(&mut scenario, INVESTOR1);
        {
            let mut project = ts::take_from_address<BondProject>(&scenario, ISSUER);
            let payment = coin::mint_for_testing<SUI>(5 * TOKEN_PRICE, ts::ctx(&mut scenario));
            blue_link::buy_bond_tokens(&mut project, 5, payment, ts::ctx(&mut scenario));
            ts::return_to_address(ISSUER, project);
        };
        
        // Issuer deposits redemption funds (principal + interest)
        ts::next_tx(&mut scenario, ISSUER);
        {
            let mut project = ts::take_from_sender<BondProject>(&scenario);
            let redemption_amount = 150 * TOKEN_PRICE; // Enough for all tokens + interest
            let payment = coin::mint_for_testing<SUI>(redemption_amount, ts::ctx(&mut scenario));
            blue_link::deposit_redemption_funds(&mut project, payment, ts::ctx(&mut scenario));
            ts::return_to_sender(&scenario, project);
        };
        
        // Fast forward time to maturity
        ts::next_tx(&mut scenario, INVESTOR1);
        
        // Investor redeems one token
        {
            let mut project = ts::take_from_address<BondProject>(&scenario, ISSUER);
            let token = ts::take_from_sender<BondToken>(&scenario);
            
            blue_link::redeem_bond_token(&mut project, token, ts::ctx(&mut scenario));
            
            let (_, _, _, _, _, _, tokens_redeemed, _, _, _, _, _) = 
                blue_link::get_bond_project_info(&project);
            assert!(tokens_redeemed == 1, 0);
            
            ts::return_to_address(ISSUER, project);
        };
        
        // Verify investor received redemption payment
        ts::next_tx(&mut scenario, INVESTOR1);
        {
            let redemption_coin = ts::take_from_sender<Coin<SUI>>(&scenario);
            assert!(coin::value(&redemption_coin) > TOKEN_PRICE, 1); // Should be principal + interest
            test_utils::destroy(redemption_coin);
        };
        
        ts::end(scenario);
    }

    // Test 12: Cannot redeem before maturity
    #[test]
    #[expected_failure(abort_code = EBondNotMatured)]
    fun test_redeem_before_maturity() {
        let mut scenario = setup_test();
        
        // Create bond with future maturity date
        ts::next_tx(&mut scenario, ISSUER);
        {
            blue_link::create_bond_project(
                b"Test Bond",
                b"Issuer",
                b"Description",
                TOTAL_SUPPLY,
                TOKEN_PRICE,
                ANNUAL_RATE,
                1000000, // Far future maturity
                ts::ctx(&mut scenario)
            );
        };
        
        // Investor buys token
        ts::next_tx(&mut scenario, INVESTOR1);
        {
            let mut project = ts::take_from_address<BondProject>(&scenario, ISSUER);
            let payment = coin::mint_for_testing<SUI>(TOKEN_PRICE, ts::ctx(&mut scenario));
            blue_link::buy_bond_tokens(&mut project, 1, payment, ts::ctx(&mut scenario));
            ts::return_to_address(ISSUER, project);
        };
        
        // Issuer deposits redemption funds
        ts::next_tx(&mut scenario, ISSUER);
        {
            let mut project = ts::take_from_sender<BondProject>(&scenario);
            let payment = coin::mint_for_testing<SUI>(2 * TOKEN_PRICE, ts::ctx(&mut scenario));
            blue_link::deposit_redemption_funds(&mut project, payment, ts::ctx(&mut scenario));
            ts::return_to_sender(&scenario, project);
        };
        
        // Try to redeem before maturity
        ts::next_tx(&mut scenario, INVESTOR1);
        {
            let mut project = ts::take_from_address<BondProject>(&scenario, ISSUER);
            let token = ts::take_from_sender<BondToken>(&scenario);
            blue_link::redeem_bond_token(&mut project, token, ts::ctx(&mut scenario));
            ts::return_to_address(ISSUER, project);
        };
        
        ts::end(scenario);
    }

    // Test 13: View functions work correctly
    #[test]
    fun test_view_functions() {
        let mut scenario = setup_test();
        
        create_test_bond_project(&mut scenario);
        
        ts::next_tx(&mut scenario, ISSUER);
        {
            let project = ts::take_from_sender<BondProject>(&scenario);
            
            // Test get_available_tokens
            let available = blue_link::get_available_tokens(&project);
            assert!(available == TOTAL_SUPPLY, 0);
            
            // Test is_bond_matured
            let is_matured = blue_link::is_bond_matured(&project, MATURITY_DATE + 1);
            assert!(is_matured == true, 1);
            
            let not_matured = blue_link::is_bond_matured(&project, MATURITY_DATE - 1);
            assert!(not_matured == false, 2);
            
            // Test get_total_market_value
            let market_value = blue_link::get_total_market_value(&project);
            assert!(market_value == TOTAL_SUPPLY * TOKEN_PRICE, 3);
            
            ts::return_to_sender(&scenario, project);
        };
        
        ts::end(scenario);
    }
}
