#[test_only]
module blue_link::blue_link_tests {
    use sui::test_scenario::{Self as ts, Scenario};
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use sui::test_utils;
    use sui::clock::{Self, Clock};
    use blue_link::blue_link::{Self, BondProject, BondToken};
    use std::string;

    // Test addresses
    const ISSUER: address = @0xA;
    const INVESTOR1: address = @0xB;
    const INVESTOR2: address = @0xC;
    const RANDOM_USER: address = @0xD;

    // Test constants - 以募集總額度為基準
    const TOTAL_AMOUNT: u64 = 100_000_000_000; // 100 SUI (100 * 10^9)
    const ANNUAL_RATE: u64 = 500; // 5% (500 basis points)
    const ONE_YEAR_MS: u64 = 31536000000; // 365 days in milliseconds
    const ISSUE_TIME: u64 = 1000000000; // Arbitrary start time
    
    // Error codes from main module
    const EPurchaseAmountIsZero: u64 = 202;
    const EInsufficientTokensAvailable: u64 = 204;
    const ENotBondIssuer: u64 = 300;
    const EInsufficientFunds: u64 = 301;
    const EWithdrawAmountIsZero: u64 = 302;
    const EBondNotMatured: u64 = 400;
    const ENotTokenOwner: u64 = 401;
    const EInsufficientRedemptionFunds: u64 = 402;
    // const EBondAlreadyRedeemed: u64 = 403;
    const EInvalidParameter: u64 = 101;

    // Helper function to create a test scenario
    fun setup_test(): Scenario {
        ts::begin(ISSUER)
    }

    // Helper function to create a test clock
    fun create_clock(scenario: &mut Scenario): Clock {
        clock::create_for_testing(ts::ctx(scenario))
    }

    // Helper function to create a bond project with clock
    fun create_test_bond_project(scenario: &mut Scenario, clock: &Clock) {
        ts::next_tx(scenario, ISSUER);
        {
            let maturity_date = ISSUE_TIME + ONE_YEAR_MS;
            blue_link::create_bond_project(
                b"Palau Government",
                b"Ocean Conservation Bond 2024",
                TOTAL_AMOUNT,
                ANNUAL_RATE,
                maturity_date,
                clock,
                ts::ctx(scenario)
            );
        };
    }

    // Test 1: Create bond project
    #[test]
    fun test_create_bond_project() {
        let mut scenario = setup_test();
        let mut clock = create_clock(&mut scenario);
        clock::set_for_testing(&mut clock, ISSUE_TIME);
        
        create_test_bond_project(&mut scenario, &clock);
        
        // Verify bond project was created and transferred to issuer
        ts::next_tx(&mut scenario, ISSUER);
        {
            let project = ts::take_from_sender<BondProject>(&scenario);
            
            let (bond_name, issuer, total_amount, amount_raised, amount_redeemed,
                 tokens_issued, tokens_redeemed, annual_rate, maturity, 
                 raised_funds, redemption_pool, active_status, redeemable_status) = 
                 blue_link::get_bond_project_info(&project);
            
            assert!(bond_name == string::utf8(b"Ocean Conservation Bond 2024"), 0);
            assert!(issuer == ISSUER, 1);
            assert!(total_amount == TOTAL_AMOUNT, 2);
            assert!(amount_raised == 0, 3);
            assert!(amount_redeemed == 0, 4);
            assert!(tokens_issued == 0, 5);
            assert!(tokens_redeemed == 0, 6);
            assert!(annual_rate == ANNUAL_RATE, 7);
            assert!(maturity == ISSUE_TIME + ONE_YEAR_MS, 8);
            assert!(raised_funds == 0, 9);
            assert!(redemption_pool == 0, 10);
            assert!(active_status == true, 11);
            assert!(redeemable_status == false, 12);
            
            ts::return_to_sender(&scenario, project);
        };
        
        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    // Test 2: Buy bond tokens - creates ONE NFT per purchase
    #[test]
    fun test_buy_bond_rwa_tokens() {
        let mut scenario = setup_test();
        let mut clock = create_clock(&mut scenario);
        clock::set_for_testing(&mut clock, ISSUE_TIME);
        
        create_test_bond_project(&mut scenario, &clock);
        
        // Investor1 buys with 10 SUI (creates ONE token NFT with amount=10 SUI)
        ts::next_tx(&mut scenario, INVESTOR1);
        {
            let mut project = ts::take_from_address<BondProject>(&scenario, ISSUER);
            let payment = coin::mint_for_testing<SUI>(10_000_000_000, ts::ctx(&mut scenario)); // 10 SUI
            
            blue_link::buy_bond_rwa_tokens(&mut project, payment, &clock, ts::ctx(&mut scenario));
            
            // Verify project state
            let (_, _, _, amount_raised, _, tokens_issued, _, _, _, raised_funds, _, _, _) = 
                blue_link::get_bond_project_info(&project);
            assert!(tokens_issued == 1, 0); // Only 1 NFT created
            assert!(amount_raised == 10_000_000_000, 1);
            assert!(raised_funds == 10_000_000_000, 2);
            
            ts::return_to_address(ISSUER, project);
        };
        
        // Verify investor received 1 bond token NFT
        ts::next_tx(&mut scenario, INVESTOR1);
        {
            let token_ids = ts::ids_for_sender<BondToken>(&scenario);
            assert!(token_ids.length() == 1, 3);
            
            // Check token details
            let token = ts::take_from_sender<BondToken>(&scenario);
            let (_, token_number, owner, amount, _, is_redeemed) = 
                blue_link::get_bond_token_info(&token);
            assert!(token_number == 1, 4);
            assert!(owner == INVESTOR1, 5);
            assert!(amount == 10_000_000_000, 6);
            assert!(!is_redeemed, 7);
            
            ts::return_to_sender(&scenario, token);
        };
        
        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    // Test 3: Multiple purchases create multiple NFTs
    #[test]
    fun test_multiple_purchases() {
        let mut scenario = setup_test();
        let mut clock = create_clock(&mut scenario);
        clock::set_for_testing(&mut clock, ISSUE_TIME);
        
        create_test_bond_project(&mut scenario, &clock);
        
        // Investor1 makes first purchase (30 SUI)
        ts::next_tx(&mut scenario, INVESTOR1);
        {
            let mut project = ts::take_from_address<BondProject>(&scenario, ISSUER);
            let payment = coin::mint_for_testing<SUI>(30_000_000_000, ts::ctx(&mut scenario));
            blue_link::buy_bond_rwa_tokens(&mut project, payment, &clock, ts::ctx(&mut scenario));
            ts::return_to_address(ISSUER, project);
        };
        
        // Investor2 makes purchase (20 SUI)
        ts::next_tx(&mut scenario, INVESTOR2);
        {
            let mut project = ts::take_from_address<BondProject>(&scenario, ISSUER);
            let payment = coin::mint_for_testing<SUI>(20_000_000_000, ts::ctx(&mut scenario));
            blue_link::buy_bond_rwa_tokens(&mut project, payment, &clock, ts::ctx(&mut scenario));
            ts::return_to_address(ISSUER, project);
        };
        
        // Investor1 makes second purchase (15 SUI)
        ts::next_tx(&mut scenario, INVESTOR1);
        {
            let mut project = ts::take_from_address<BondProject>(&scenario, ISSUER);
            let payment = coin::mint_for_testing<SUI>(15_000_000_000, ts::ctx(&mut scenario));
            blue_link::buy_bond_rwa_tokens(&mut project, payment, &clock, ts::ctx(&mut scenario));
            ts::return_to_address(ISSUER, project);
        };
        
        // Verify project state: 3 tokens issued, 65 SUI raised
        ts::next_tx(&mut scenario, ISSUER);
        {
            let project = ts::take_from_sender<BondProject>(&scenario);
            let (_, _, _, amount_raised, _, tokens_issued, _, _, _, _, _, _, _) = 
                blue_link::get_bond_project_info(&project);
            assert!(tokens_issued == 3, 0);
            assert!(amount_raised == 65_000_000_000, 1);
            ts::return_to_sender(&scenario, project);
        };
        
        // Investor1 should have 2 NFTs
        ts::next_tx(&mut scenario, INVESTOR1);
        {
            let token_ids = ts::ids_for_sender<BondToken>(&scenario);
            assert!(token_ids.length() == 2, 2);
        };
        
        // Investor2 should have 1 NFT
        ts::next_tx(&mut scenario, INVESTOR2);
        {
            let token_ids = ts::ids_for_sender<BondToken>(&scenario);
            assert!(token_ids.length() == 1, 3);
        };
        
        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    // Test 4: Cannot buy with zero amount
    #[test]
    #[expected_failure(abort_code = EPurchaseAmountIsZero)]
    fun test_buy_zero_amount() {
        let mut scenario = setup_test();
        let mut clock = create_clock(&mut scenario);
        clock::set_for_testing(&mut clock, ISSUE_TIME);
        
        create_test_bond_project(&mut scenario, &clock);
        
        ts::next_tx(&mut scenario, INVESTOR1);
        {
            let mut project = ts::take_from_address<BondProject>(&scenario, ISSUER);
            let payment = coin::mint_for_testing<SUI>(0, ts::ctx(&mut scenario));
            blue_link::buy_bond_rwa_tokens(&mut project, payment, &clock, ts::ctx(&mut scenario));
            ts::return_to_address(ISSUER, project);
        };
        
        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    // Test 5: Cannot exceed total amount capacity
    #[test]
    #[expected_failure(abort_code = EInsufficientTokensAvailable)]
    fun test_buy_exceeds_capacity() {
        let mut scenario = setup_test();
        let mut clock = create_clock(&mut scenario);
        clock::set_for_testing(&mut clock, ISSUE_TIME);
        
        create_test_bond_project(&mut scenario, &clock);
        
        ts::next_tx(&mut scenario, INVESTOR1);
        {
            let mut project = ts::take_from_address<BondProject>(&scenario, ISSUER);
            // Try to buy more than total amount (100 SUI)
            let payment = coin::mint_for_testing<SUI>(150_000_000_000, ts::ctx(&mut scenario));
            blue_link::buy_bond_rwa_tokens(&mut project, payment, &clock, ts::ctx(&mut scenario));
            ts::return_to_address(ISSUER, project);
        };
        
        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    // Test 6: Sale auto-closes when fully funded
    #[test]
    fun test_auto_close_when_fully_funded() {
        let mut scenario = setup_test();
        let mut clock = create_clock(&mut scenario);
        clock::set_for_testing(&mut clock, ISSUE_TIME);
        
        create_test_bond_project(&mut scenario, &clock);
        
        // Buy exactly the total amount
        ts::next_tx(&mut scenario, INVESTOR1);
        {
            let mut project = ts::take_from_address<BondProject>(&scenario, ISSUER);
            let payment = coin::mint_for_testing<SUI>(TOTAL_AMOUNT, ts::ctx(&mut scenario));
            blue_link::buy_bond_rwa_tokens(&mut project, payment, &clock, ts::ctx(&mut scenario));
            
            // Verify sale is now closed (active = false)
            let (_, _, _, _, _, _, _, _, _, _, _, active, _) = 
                blue_link::get_bond_project_info(&project);
            assert!(!active, 0);
            
            ts::return_to_address(ISSUER, project);
        };
        
        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    // Test 7: Cannot buy when sale is paused
    #[test]
    #[expected_failure(abort_code = EInvalidParameter)]
    fun test_buy_when_paused() {
        let mut scenario = setup_test();
        let mut clock = create_clock(&mut scenario);
        clock::set_for_testing(&mut clock, ISSUE_TIME);
        
        create_test_bond_project(&mut scenario, &clock);
        
        // Issuer pauses the sale
        ts::next_tx(&mut scenario, ISSUER);
        {
            let mut project = ts::take_from_sender<BondProject>(&scenario);
            blue_link::pause_sale(&mut project, ts::ctx(&mut scenario));
            ts::return_to_sender(&scenario, project);
        };
        
        // Try to buy when paused
        ts::next_tx(&mut scenario, INVESTOR1);
        {
            let mut project = ts::take_from_address<BondProject>(&scenario, ISSUER);
            let payment = coin::mint_for_testing<SUI>(10_000_000_000, ts::ctx(&mut scenario));
            blue_link::buy_bond_rwa_tokens(&mut project, payment, &clock, ts::ctx(&mut scenario));
            ts::return_to_address(ISSUER, project);
        };
        
        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    // Test 8: Pause and resume sale
    #[test]
    fun test_pause_and_resume_sale() {
        let mut scenario = setup_test();
        let mut clock = create_clock(&mut scenario);
        clock::set_for_testing(&mut clock, ISSUE_TIME);
        
        create_test_bond_project(&mut scenario, &clock);
        
        // Issuer pauses the sale
        ts::next_tx(&mut scenario, ISSUER);
        {
            let mut project = ts::take_from_sender<BondProject>(&scenario);
            blue_link::pause_sale(&mut project, ts::ctx(&mut scenario));
            
            let (_, _, _, _, _, _, _, _, _, _, _, active, _) = 
                blue_link::get_bond_project_info(&project);
            assert!(!active, 0);
            
            ts::return_to_sender(&scenario, project);
        };
        
        // Issuer resumes the sale
        ts::next_tx(&mut scenario, ISSUER);
        {
            let mut project = ts::take_from_sender<BondProject>(&scenario);
            blue_link::resume_sale(&mut project, ts::ctx(&mut scenario));
            
            let (_, _, _, _, _, _, _, _, _, _, _, active, _) = 
                blue_link::get_bond_project_info(&project);
            assert!(active, 1);
            
            ts::return_to_sender(&scenario, project);
        };
        
        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    // Test 9: Only issuer can pause/resume
    #[test]
    #[expected_failure(abort_code = ENotBondIssuer)]
    fun test_pause_not_issuer() {
        let mut scenario = setup_test();
        let mut clock = create_clock(&mut scenario);
        clock::set_for_testing(&mut clock, ISSUE_TIME);
        
        create_test_bond_project(&mut scenario, &clock);
        
        ts::next_tx(&mut scenario, RANDOM_USER);
        {
            let mut project = ts::take_from_address<BondProject>(&scenario, ISSUER);
            blue_link::pause_sale(&mut project, ts::ctx(&mut scenario));
            ts::return_to_address(ISSUER, project);
        };
        
        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    // Test 10: Issuer withdraws raised funds
    #[test]
    fun test_withdraw_raised_funds() {
        let mut scenario = setup_test();
        let mut clock = create_clock(&mut scenario);
        clock::set_for_testing(&mut clock, ISSUE_TIME);
        
        create_test_bond_project(&mut scenario, &clock);
        
        // Investor buys tokens
        ts::next_tx(&mut scenario, INVESTOR1);
        {
            let mut project = ts::take_from_address<BondProject>(&scenario, ISSUER);
            let payment = coin::mint_for_testing<SUI>(50_000_000_000, ts::ctx(&mut scenario)); // 50 SUI
            blue_link::buy_bond_rwa_tokens(&mut project, payment, &clock, ts::ctx(&mut scenario));
            ts::return_to_address(ISSUER, project);
        };
        
        // Issuer withdraws 30 SUI
        ts::next_tx(&mut scenario, ISSUER);
        {
            let mut project = ts::take_from_sender<BondProject>(&scenario);
            blue_link::withdraw_raised_funds(&mut project, 30_000_000_000, ts::ctx(&mut scenario));
            
            let (_, _, _, _, _, _, _, _, _, raised_funds, _, _, _) = 
                blue_link::get_bond_project_info(&project);
            assert!(raised_funds == 20_000_000_000, 0); // 50 - 30 = 20 SUI remaining
            
            ts::return_to_sender(&scenario, project);
        };
        
        // Verify issuer received the withdrawal
        ts::next_tx(&mut scenario, ISSUER);
        {
            let withdrawn_coin = ts::take_from_sender<Coin<SUI>>(&scenario);
            assert!(coin::value(&withdrawn_coin) == 30_000_000_000, 1);
            test_utils::destroy(withdrawn_coin);
        };
        
        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    // Test 11: Cannot withdraw zero amount
    #[test]
    #[expected_failure(abort_code = EWithdrawAmountIsZero)]
    fun test_withdraw_zero_amount() {
        let mut scenario = setup_test();
        let mut clock = create_clock(&mut scenario);
        clock::set_for_testing(&mut clock, ISSUE_TIME);
        
        create_test_bond_project(&mut scenario, &clock);
        
        ts::next_tx(&mut scenario, ISSUER);
        {
            let mut project = ts::take_from_sender<BondProject>(&scenario);
            blue_link::withdraw_raised_funds(&mut project, 0, ts::ctx(&mut scenario));
            ts::return_to_sender(&scenario, project);
        };
        
        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    // Test 12: Non-issuer cannot withdraw funds
    #[test]
    #[expected_failure(abort_code = ENotBondIssuer)]
    fun test_withdraw_not_issuer() {
        let mut scenario = setup_test();
        let mut clock = create_clock(&mut scenario);
        clock::set_for_testing(&mut clock, ISSUE_TIME);
        
        create_test_bond_project(&mut scenario, &clock);
        
        // Investor buys tokens
        ts::next_tx(&mut scenario, INVESTOR1);
        {
            let mut project = ts::take_from_address<BondProject>(&scenario, ISSUER);
            let payment = coin::mint_for_testing<SUI>(10_000_000_000, ts::ctx(&mut scenario));
            blue_link::buy_bond_rwa_tokens(&mut project, payment, &clock, ts::ctx(&mut scenario));
            ts::return_to_address(ISSUER, project);
        };
        
        // Random user tries to withdraw
        ts::next_tx(&mut scenario, RANDOM_USER);
        {
            let mut project = ts::take_from_address<BondProject>(&scenario, ISSUER);
            blue_link::withdraw_raised_funds(&mut project, 1_000_000_000, ts::ctx(&mut scenario));
            ts::return_to_address(ISSUER, project);
        };
        
        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    // Test 13: Cannot withdraw more than available
    #[test]
    #[expected_failure(abort_code = EInsufficientFunds)]
    fun test_withdraw_exceeds_balance() {
        let mut scenario = setup_test();
        let mut clock = create_clock(&mut scenario);
        clock::set_for_testing(&mut clock, ISSUE_TIME);
        
        create_test_bond_project(&mut scenario, &clock);
        
        // Investor buys tokens
        ts::next_tx(&mut scenario, INVESTOR1);
        {
            let mut project = ts::take_from_address<BondProject>(&scenario, ISSUER);
            let payment = coin::mint_for_testing<SUI>(10_000_000_000, ts::ctx(&mut scenario));
            blue_link::buy_bond_rwa_tokens(&mut project, payment, &clock, ts::ctx(&mut scenario));
            ts::return_to_address(ISSUER, project);
        };
        
        // Try to withdraw more than raised
        ts::next_tx(&mut scenario, ISSUER);
        {
            let mut project = ts::take_from_sender<BondProject>(&scenario);
            blue_link::withdraw_raised_funds(&mut project, 20_000_000_000, ts::ctx(&mut scenario));
            ts::return_to_sender(&scenario, project);
        };
        
        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    // Test 14: Deposit redemption funds
    #[test]
    fun test_deposit_redemption_funds() {
        let mut scenario = setup_test();
        let mut clock = create_clock(&mut scenario);
        clock::set_for_testing(&mut clock, ISSUE_TIME);
        
        create_test_bond_project(&mut scenario, &clock);
        
        // Issuer deposits redemption funds before maturity
        ts::next_tx(&mut scenario, ISSUER);
        {
            let mut project = ts::take_from_sender<BondProject>(&scenario);
            let payment = coin::mint_for_testing<SUI>(120_000_000_000, ts::ctx(&mut scenario)); // 120 SUI
            blue_link::deposit_redemption_funds(&mut project, payment, &clock, ts::ctx(&mut scenario));
            
            let (_, _, _, _, _, _, _, _, _, _, redemption_pool, _, redeemable) = 
                blue_link::get_bond_project_info(&project);
            assert!(redemption_pool == 120_000_000_000, 0);
            assert!(!redeemable, 1); // Not redeemable yet (before maturity)
            
            ts::return_to_sender(&scenario, project);
        };
        
        // Set time to maturity and deposit more funds
        clock::set_for_testing(&mut clock, ISSUE_TIME + ONE_YEAR_MS);
        ts::next_tx(&mut scenario, ISSUER);
        {
            let mut project = ts::take_from_sender<BondProject>(&scenario);
            let payment = coin::mint_for_testing<SUI>(10_000_000_000, ts::ctx(&mut scenario));
            blue_link::deposit_redemption_funds(&mut project, payment, &clock, ts::ctx(&mut scenario));
            
            let (_, _, _, _, _, _, _, _, _, _, redemption_pool, _, redeemable) = 
                blue_link::get_bond_project_info(&project);
            assert!(redemption_pool == 130_000_000_000, 2);
            assert!(redeemable, 3); // Now redeemable
            
            ts::return_to_sender(&scenario, project);
        };
        
        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    // Test 15: Non-issuer cannot deposit redemption funds
    #[test]
    #[expected_failure(abort_code = ENotBondIssuer)]
    fun test_deposit_redemption_not_issuer() {
        let mut scenario = setup_test();
        let mut clock = create_clock(&mut scenario);
        clock::set_for_testing(&mut clock, ISSUE_TIME);
        
        create_test_bond_project(&mut scenario, &clock);
        
        ts::next_tx(&mut scenario, RANDOM_USER);
        {
            let mut project = ts::take_from_address<BondProject>(&scenario, ISSUER);
            let payment = coin::mint_for_testing<SUI>(10_000_000_000, ts::ctx(&mut scenario));
            blue_link::deposit_redemption_funds(&mut project, payment, &clock, ts::ctx(&mut scenario));
            ts::return_to_address(ISSUER, project);
        };
        
        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    // Test 16: Redeem bond token successfully
    #[test]
    fun test_redeem_bond_token_success() {
        let mut scenario = setup_test();
        let mut clock = create_clock(&mut scenario);
        clock::set_for_testing(&mut clock, ISSUE_TIME);
        
        create_test_bond_project(&mut scenario, &clock);
        
        // Investor buys tokens
        ts::next_tx(&mut scenario, INVESTOR1);
        {
            let mut project = ts::take_from_address<BondProject>(&scenario, ISSUER);
            let payment = coin::mint_for_testing<SUI>(20_000_000_000, ts::ctx(&mut scenario)); // 20 SUI
            blue_link::buy_bond_rwa_tokens(&mut project, payment, &clock, ts::ctx(&mut scenario));
            ts::return_to_address(ISSUER, project);
        };
        
        // Fast forward to maturity date
        clock::set_for_testing(&mut clock, ISSUE_TIME + ONE_YEAR_MS);
        
        // Issuer deposits redemption funds (principal + interest)
        ts::next_tx(&mut scenario, ISSUER);
        {
            let mut project = ts::take_from_sender<BondProject>(&scenario);
            // Principal: 20 SUI, Interest (5% for 1 year): 1 SUI, Total: 21 SUI
            let redemption_amount = 21_000_000_000;
            let payment = coin::mint_for_testing<SUI>(redemption_amount, ts::ctx(&mut scenario));
            blue_link::deposit_redemption_funds(&mut project, payment, &clock, ts::ctx(&mut scenario));
            ts::return_to_sender(&scenario, project);
        };
        
        // Investor redeems token
        ts::next_tx(&mut scenario, INVESTOR1);
        {
            let mut project = ts::take_from_address<BondProject>(&scenario, ISSUER);
            let token = ts::take_from_sender<BondToken>(&scenario);
            
            blue_link::redeem_bond_token(&mut project, token, &clock, ts::ctx(&mut scenario));
            
            let (_, _, _, _, amount_redeemed, _, tokens_redeemed, _, _, _, _, _, _) = 
                blue_link::get_bond_project_info(&project);
            assert!(tokens_redeemed == 1, 0);
            assert!(amount_redeemed == 20_000_000_000, 1);
            
            ts::return_to_address(ISSUER, project);
        };
        
        // Verify investor received redemption payment (principal + interest)
        ts::next_tx(&mut scenario, INVESTOR1);
        {
            let redemption_coin = ts::take_from_sender<Coin<SUI>>(&scenario);
            let amount = coin::value(&redemption_coin);
            // Should be approximately 21 SUI (20 principal + 1 interest)
            assert!(amount > 20_000_000_000, 2);
            assert!(amount <= 21_000_000_000, 3);
            test_utils::destroy(redemption_coin);
        };
        
        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    // Test 17: Cannot redeem before maturity
    #[test]
    #[expected_failure(abort_code = EBondNotMatured)]
    fun test_redeem_before_maturity() {
        let mut scenario = setup_test();
        let mut clock = create_clock(&mut scenario);
        clock::set_for_testing(&mut clock, ISSUE_TIME);
        
        create_test_bond_project(&mut scenario, &clock);
        
        // Investor buys token
        ts::next_tx(&mut scenario, INVESTOR1);
        {
            let mut project = ts::take_from_address<BondProject>(&scenario, ISSUER);
            let payment = coin::mint_for_testing<SUI>(10_000_000_000, ts::ctx(&mut scenario));
            blue_link::buy_bond_rwa_tokens(&mut project, payment, &clock, ts::ctx(&mut scenario));
            ts::return_to_address(ISSUER, project);
        };
        
        // Issuer deposits redemption funds
        ts::next_tx(&mut scenario, ISSUER);
        {
            let mut project = ts::take_from_sender<BondProject>(&scenario);
            let payment = coin::mint_for_testing<SUI>(12_000_000_000, ts::ctx(&mut scenario));
            blue_link::deposit_redemption_funds(&mut project, payment, &clock, ts::ctx(&mut scenario));
            ts::return_to_sender(&scenario, project);
        };
        
        // Try to redeem before maturity (still at ISSUE_TIME)
        ts::next_tx(&mut scenario, INVESTOR1);
        {
            let mut project = ts::take_from_address<BondProject>(&scenario, ISSUER);
            let token = ts::take_from_sender<BondToken>(&scenario);
            blue_link::redeem_bond_token(&mut project, token, &clock, ts::ctx(&mut scenario));
            ts::return_to_address(ISSUER, project);
        };
        
        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

        // Test 18: Cannot redeem if insufficient redemption funds
    #[test]
    #[expected_failure(abort_code = EInsufficientRedemptionFunds)]
    fun test_redeem_insufficient_funds() {
        let mut scenario = setup_test();
        let mut clock = create_clock(&mut scenario);
        clock::set_for_testing(&mut clock, ISSUE_TIME);
        
        create_test_bond_project(&mut scenario, &clock);
        
        // Investor buys tokens
        ts::next_tx(&mut scenario, INVESTOR1);
        {
            let mut project = ts::take_from_address<BondProject>(&scenario, ISSUER);
            let payment = coin::mint_for_testing<SUI>(50_000_000_000, ts::ctx(&mut scenario));
            blue_link::buy_bond_rwa_tokens(&mut project, payment, &clock, ts::ctx(&mut scenario));
            ts::return_to_address(ISSUER, project);
        };
        
        // Fast forward to maturity
        clock::set_for_testing(&mut clock, ISSUE_TIME + ONE_YEAR_MS);
        
        // Issuer deposits insufficient redemption funds
        ts::next_tx(&mut scenario, ISSUER);
        {
            let mut project = ts::take_from_sender<BondProject>(&scenario);
            let payment = coin::mint_for_testing<SUI>(10_000_000_000, ts::ctx(&mut scenario)); // Only 10 SUI
            blue_link::deposit_redemption_funds(&mut project, payment, &clock, ts::ctx(&mut scenario));
            ts::return_to_sender(&scenario, project);
        };
        
        // Try to redeem (should fail - needs ~52.5 SUI but only 10 SUI available)
        ts::next_tx(&mut scenario, INVESTOR1);
        {
            let mut project = ts::take_from_address<BondProject>(&scenario, ISSUER);
            let token = ts::take_from_sender<BondToken>(&scenario);
            blue_link::redeem_bond_token(&mut project, token, &clock, ts::ctx(&mut scenario));
            ts::return_to_address(ISSUER, project);
        };
        
        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    // Test 19: Non-owner cannot redeem token
    #[test]
    #[expected_failure(abort_code = ENotTokenOwner)]
    fun test_redeem_not_owner() {
        let mut scenario = setup_test();
        let mut clock = create_clock(&mut scenario);
        clock::set_for_testing(&mut clock, ISSUE_TIME);
        
        create_test_bond_project(&mut scenario, &clock);
        
        // Investor1 buys token
        ts::next_tx(&mut scenario, INVESTOR1);
        {
            let mut project = ts::take_from_address<BondProject>(&scenario, ISSUER);
            let payment = coin::mint_for_testing<SUI>(10_000_000_000, ts::ctx(&mut scenario));
            blue_link::buy_bond_rwa_tokens(&mut project, payment, &clock, ts::ctx(&mut scenario));
            ts::return_to_address(ISSUER, project);
        };
        
        // Fast forward to maturity and deposit funds
        clock::set_for_testing(&mut clock, ISSUE_TIME + ONE_YEAR_MS);
        ts::next_tx(&mut scenario, ISSUER);
        {
            let mut project = ts::take_from_sender<BondProject>(&scenario);
            let payment = coin::mint_for_testing<SUI>(15_000_000_000, ts::ctx(&mut scenario));
            blue_link::deposit_redemption_funds(&mut project, payment, &clock, ts::ctx(&mut scenario));
            ts::return_to_sender(&scenario, project);
        };
        
        // Investor2 tries to redeem Investor1's token (should fail)
        ts::next_tx(&mut scenario, INVESTOR2);
        {
            let mut project = ts::take_from_address<BondProject>(&scenario, ISSUER);
            let token = ts::take_from_address<BondToken>(&scenario, INVESTOR1);
            blue_link::redeem_bond_token(&mut project, token, &clock, ts::ctx(&mut scenario));
            ts::return_to_address(ISSUER, project);
        };
        
        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    // Test 20: View functions work correctly
    #[test]
    fun test_view_functions() {
        let mut scenario = setup_test();
        let mut clock = create_clock(&mut scenario);
        clock::set_for_testing(&mut clock, ISSUE_TIME);
        
        create_test_bond_project(&mut scenario, &clock);
        
        // Buy some tokens
        ts::next_tx(&mut scenario, INVESTOR1);
        {
            let mut project = ts::take_from_address<BondProject>(&scenario, ISSUER);
            let payment = coin::mint_for_testing<SUI>(30_000_000_000, ts::ctx(&mut scenario));
            blue_link::buy_bond_rwa_tokens(&mut project, payment, &clock, ts::ctx(&mut scenario));
            ts::return_to_address(ISSUER, project);
        };
        
        ts::next_tx(&mut scenario, ISSUER);
        {
            let project = ts::take_from_sender<BondProject>(&scenario);
            
            // Test get_available_capacity
            let available = blue_link::get_available_capacity(&project);
            assert!(available == 70_000_000_000, 0); // 100 - 30 = 70 SUI
            
            // Test get_sale_progress
            let (amount_raised, total_amount, percentage) = blue_link::get_sale_progress(&project);
            assert!(amount_raised == 30_000_000_000, 1);
            assert!(total_amount == TOTAL_AMOUNT, 2);
            assert!(percentage == 30, 3); // 30%
            
            // Test get_total_raised
            let total_raised = blue_link::get_total_raised(&project);
            assert!(total_raised == 30_000_000_000, 4);
            
            // Test get_redemption_pool_balance
            let pool_balance = blue_link::get_redemption_pool_balance(&project);
            assert!(pool_balance == 0, 5);
            
            // Test get_tokens_pending_redemption
            let pending = blue_link::get_tokens_pending_redemption(&project);
            assert!(pending == 1, 6); // 1 token issued, 0 redeemed
            
            ts::return_to_sender(&scenario, project);
        };
        
        // Test bond token info
        ts::next_tx(&mut scenario, INVESTOR1);
        {
            let token = ts::take_from_sender<BondToken>(&scenario);
            let (_, token_number, owner, amount, purchase_date, is_redeemed) = 
                blue_link::get_bond_token_info(&token);
            
            assert!(token_number == 1, 7);
            assert!(owner == INVESTOR1, 8);
            assert!(amount == 30_000_000_000, 9);
            assert!(purchase_date == ISSUE_TIME, 10);
            assert!(!is_redeemed, 11);
            
            ts::return_to_sender(&scenario, token);
        };
        
        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    // Test 21: Interest calculation with partial year holding
    #[test]
    fun test_interest_calculation_partial_year() {
        let mut scenario = setup_test();
        let mut clock = create_clock(&mut scenario);
        clock::set_for_testing(&mut clock, ISSUE_TIME);
        
        create_test_bond_project(&mut scenario, &clock);
        
        // Buy token
        ts::next_tx(&mut scenario, INVESTOR1);
        {
            let mut project = ts::take_from_address<BondProject>(&scenario, ISSUER);
            let payment = coin::mint_for_testing<SUI>(100_000_000_000, ts::ctx(&mut scenario)); // 100 SUI
            blue_link::buy_bond_rwa_tokens(&mut project, payment, &clock, ts::ctx(&mut scenario));
            ts::return_to_address(ISSUER, project);
        };
        
        // Test calculate_redemption_amount at maturity (1 year)
        clock::set_for_testing(&mut clock, ISSUE_TIME + ONE_YEAR_MS);
        ts::next_tx(&mut scenario, INVESTOR1);
        {
            let project = ts::take_from_address<BondProject>(&scenario, ISSUER);
            let token = ts::take_from_sender<BondToken>(&scenario);
            
            let redemption_amount = blue_link::calculate_redemption_amount(&project, &token, &clock);
            // 100 SUI * 5% = 5 SUI interest
            // Total should be 105 SUI
            assert!(redemption_amount == 105_000_000_000, 0);
            
            ts::return_to_sender(&scenario, token);
            ts::return_to_address(ISSUER, project);
        };
        
        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    // Test 22: Check is_bond_redeemable function
    #[test]
    fun test_is_bond_redeemable() {
        let mut scenario = setup_test();
        let mut clock = create_clock(&mut scenario);
        clock::set_for_testing(&mut clock, ISSUE_TIME);
        
        create_test_bond_project(&mut scenario, &clock);
        
        // Before maturity and no redemption funds
        ts::next_tx(&mut scenario, ISSUER);
        {
            let project = ts::take_from_sender<BondProject>(&scenario);
            let is_redeemable = blue_link::is_bond_redeemable(&project, &clock);
            assert!(!is_redeemable, 0);
            ts::return_to_sender(&scenario, project);
        };
        
        // At maturity but no redemption funds deposited
        clock::set_for_testing(&mut clock, ISSUE_TIME + ONE_YEAR_MS);
        ts::next_tx(&mut scenario, ISSUER);
        {
            let project = ts::take_from_sender<BondProject>(&scenario);
            let is_redeemable = blue_link::is_bond_redeemable(&project, &clock);
            assert!(!is_redeemable, 1); // Still not redeemable
            ts::return_to_sender(&scenario, project);
        };
        
        // At maturity with redemption funds deposited
        ts::next_tx(&mut scenario, ISSUER);
        {
            let mut project = ts::take_from_sender<BondProject>(&scenario);
            let payment = coin::mint_for_testing<SUI>(10_000_000_000, ts::ctx(&mut scenario));
            blue_link::deposit_redemption_funds(&mut project, payment, &clock, ts::ctx(&mut scenario));
            
            let is_redeemable = blue_link::is_bond_redeemable(&project, &clock);
            assert!(is_redeemable, 2); // Now redeemable
            
            ts::return_to_sender(&scenario, project);
        };
        
        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }
}