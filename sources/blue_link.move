module blue_link::blue_link {

    use sui::coin::{Self, Coin};
    use sui::balance::{Self, Balance};
    use sui::event;
    use sui::sui::SUI; // will use USDC or self-minted coin as currency.
    use sui::clock::{Self, Clock};
    use std::string::{Self, String};
    use sui::display;
    use sui::package;

    
    // --- Error codes ---
    // General errors
    const EInvalidAmount: u64 = 100; // Invalid amount
    const EInvalidParameter: u64 = 101; // Invalid parameter

    // Purchase related errors (2xx)
    const EPurchaseAmountIsZero: u64 = 202; // Purchase amount must be greater than zero
    const EInsufficientTokensAvailable: u64 = 204; // Not enough capacity available
    
    // Bond management errors (3xx)
    const ENotBondIssuer: u64 = 300; // Only bond issuer can perform this action
    const EInsufficientFunds: u64 = 301; // Insufficient funds
    const EWithdrawAmountIsZero: u64 = 302; // Withdrawal amount must be greater than zero
    
    // Redemption related errors (4xx)
    const EBondNotMatured: u64 = 400; // Bond has not matured yet
    const ENotTokenOwner: u64 = 401; // Only token owner can redeem
    const EInsufficientRedemptionFunds: u64 = 402; // Insufficient redemption funds
    const EBondAlreadyRedeemed: u64 = 403; // Bond token already redeemed

    // --- One-Time Witness for Display ---
    public struct BLUE_LINK has drop {}


    // --- Struct definitions ---
    // Bond project - represents a tokenized bond
    public struct BondProject has key, store {
        id: UID,
        issuer: address, // Bond issuer
        issuer_name: String,
        bond_name: String,
        bond_image_url: String, // URL for bond project image (displayed on project page)
        token_image_url: String, // URL for minted token NFT image (different from project image)
        total_amount: u64, // Total bond amount (募集總額度)
        amount_raised: u64, // Amount already raised (已募集金額)
        amount_redeemed: u64, // Amount already redeemed (已贖回金額)
        tokens_issued: u64, // Number of bond tokens issued (發行的債券代幣數量)
        tokens_redeemed: u64, // Number of tokens redeemed
        annual_interest_rate: u64, // Annual interest rate in basis points (e.g., 500 = 5%)
        maturity_date: u64, // Unix timestamp of maturity date
        issue_date: u64, // Unix timestamp of issue date
        active: bool, // Bond status (active / closed)
        redeemable: bool, // Whether bond is redeemable
        raised_funds: Balance<SUI>, // Funds raised from token sales
        redemption_pool: Balance<SUI>, // Pool for redemption (principal + interest)
        metadata_url: String,  // URL pointing to full metadata (Arweave)
    }

    // Bond token NFT - represents ownership of a portion of the bond
    public struct BondToken has key, store {
        id: UID,
        project_id: ID, // Associated bond project
        bond_name: String, // Bond name (copied from project for display)
        token_image_url: String, // URL for NFT image (different from project image)
        token_number: u64, // Sequential token number
        owner: address, // Token owner
        amount: u64, // Amount invested in this token (購買金額)
        purchase_date: u64, // Unix timestamp of purchase
        maturity_date: u64, // Unix timestamp of maturity date (copied from project)
        annual_interest_rate: u64, // Annual interest rate in basis points (copied from project)
        is_redeemed: bool, // Whether token has been redeemed
    }

    // Bond project created event
    public struct BondProjectCreated has copy, drop {
        id: ID,
        issuer: address,
        bond_name: String,
        total_supply: u64,
        price: u64,
        annual_interest_rate: u64,
        maturity_date: u64,
    }

    // Bond tokens purchased event
    public struct BondTokensPurchased has copy, drop {
        project_id: ID,
        buyer: address,
        token_id: ID,  // Single token ID
        amount: u64,   // Purchase amount
    }

    // Redemption funds deposited event
    public struct RedemptionFundsDeposited has copy, drop {
        project_id: ID,
        issuer: address,
        amount: u64,
    }

    // Bond token redeemed event
    public struct BondTokenRedeemed has copy, drop {
        project_id: ID,
        token_id: ID,
        redeemer: address,
        redemption_amount: u64,
    }

    // Funds withdrawn event
    public struct FundsWithdrawn has copy, drop {
        project_id: ID,
        withdrawer: address,
        amount: u64,
    }

    // Sale paused event
    public struct SalePaused has copy, drop {
        project_id: ID,
        paused_by: address,
    }

    // Sale resumed event
    public struct SaleResumed has copy, drop {
        project_id: ID,
        resumed_by: address,
    }


    // --- Module Initializer ---
    // This function is called once when the module is published
    fun init(otw: BLUE_LINK, ctx: &mut TxContext) {
        // Claim publisher capability
        let publisher = package::claim(otw, ctx);
        
        // Create display for BondToken NFT
        let mut bond_token_display = display::new<BondToken>(&publisher, ctx);
        
        // Set display fields - these will be shown in wallets and NFT marketplaces
        display::add(&mut bond_token_display, string::utf8(b"name"), string::utf8(b"Related Bond: {bond_name}"));
        display::add(&mut bond_token_display, string::utf8(b"description"), string::utf8(b"Investment Amount: {amount} SUI | Annual Interest Rate: {annual_interest_rate} basis points"));
        display::add(&mut bond_token_display, string::utf8(b"image_url"), string::utf8(b"{token_image_url}"));

        // Update the display object
        display::update_version(&mut bond_token_display);
        
        // Transfer display and publisher to sender
        transfer::public_transfer(bond_token_display, tx_context::sender(ctx));
        transfer::public_transfer(publisher, tx_context::sender(ctx));
    }


    // --- Entry Functions ---
    
    // Create a new bond project
    entry fun create_bond_project(
        issuer_name: vector<u8>,
        bond_name: vector<u8>,
        bond_image_url: vector<u8>, // Image URL for the bond project
        token_image_url: vector<u8>, // Image URL for minted token NFTs 
        total_amount: u64, // Total bond amount to raise (募集總額度)
        annual_interest_rate: u64, // in basis points
        maturity_date: u64, // Unix timestamp in milliseconds
        metadata_url: vector<u8>, // URL pointing to full metadata (Arweave),
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        assert!(total_amount > 0, EInvalidParameter);
        
        let issuer = tx_context::sender(ctx);
        let project_id = object::new(ctx);
        let project_id_copy = object::uid_to_inner(&project_id);
        let issue_date = clock::timestamp_ms(clock);
        
        // Create bond project object on-chain
        let project = BondProject {
            id: project_id,
            issuer,
            issuer_name: string::utf8(issuer_name),
            bond_name: string::utf8(bond_name),
            bond_image_url: string::utf8(bond_image_url),
            token_image_url: string::utf8(token_image_url),
            total_amount,
            amount_raised: 0,
            amount_redeemed: 0,
            tokens_issued: 0,
            tokens_redeemed: 0,
            annual_interest_rate,
            maturity_date,
            issue_date,
            active: true,
            redeemable: false,
            raised_funds: balance::zero<SUI>(),
            redemption_pool: balance::zero<SUI>(),
            metadata_url: string::utf8(metadata_url),
        };

        // Emit event of creating bond projects
        event::emit(BondProjectCreated {
            id: project_id_copy,
            issuer,
            bond_name: project.bond_name,
            total_supply: total_amount,
            price: 0, // No longer applicable
            annual_interest_rate,
            maturity_date,
        });

        transfer::public_transfer(project, issuer);
    }

    // Buy bond tokens - create ONE NFT for the purchase amount
    entry fun buy_bond_rwa_tokens(
        project: &mut BondProject,
        payment: Coin<SUI>,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let purchase_amount = coin::value(&payment);
        assert!(purchase_amount > 0, EPurchaseAmountIsZero);
        assert!(project.active, EInvalidParameter); // Check if sale is active
        
        // Check if enough capacity remains
        let remaining_capacity = project.total_amount - project.amount_raised;
        assert!(remaining_capacity >= purchase_amount, EInsufficientTokensAvailable);
        
        let buyer = tx_context::sender(ctx);
        let project_id = object::uid_to_inner(&project.id);
        let purchase_date = clock::timestamp_ms(clock);
        
        // Add payment to raised funds
        let payment_balance = coin::into_balance(payment);
        balance::join(&mut project.raised_funds, payment_balance);
        
        // Create ONE bond token NFT with the purchase amount
        let token_id = object::new(ctx);
        let token_id_copy = object::uid_to_inner(&token_id);
        
        let token = BondToken {
            id: token_id,
            project_id,
            bond_name: project.bond_name, // Copy bond name for display
            token_image_url: project.token_image_url, // Use token-specific image URL
            token_number: project.tokens_issued + 1,
            owner: buyer,
            amount: purchase_amount,
            purchase_date,
            maturity_date: project.maturity_date, // Copy maturity date so token is self-contained
            annual_interest_rate: project.annual_interest_rate, // Copy interest rate for calculation
            is_redeemed: false,
        };
        
        transfer::public_transfer(token, buyer);
        
        // Update project state
        project.tokens_issued = project.tokens_issued + 1;
        project.amount_raised = project.amount_raised + purchase_amount;
        
        // Auto-close when fully funded
        if (project.amount_raised >= project.total_amount) {
            project.active = false;
        };
        
        event::emit(BondTokensPurchased {
            project_id,
            buyer,
            token_id: token_id_copy,
            amount: purchase_amount,
        });
    }

    // Issuer deposits redemption funds (principal + interest)
    entry fun deposit_redemption_funds(
        project: &mut BondProject,
        payment: Coin<SUI>,
        clock: &Clock,
        ctx: &TxContext
    ) {
        let depositor = tx_context::sender(ctx);
        assert!(project.issuer == depositor, ENotBondIssuer);
        
        let amount = coin::value(&payment);
        assert!(amount > 0, EInvalidAmount);
        
        let payment_balance = coin::into_balance(payment);
        balance::join(&mut project.redemption_pool, payment_balance);
        
        // Update status to redeemable if maturity date is reached
        let current_time = clock::timestamp_ms(clock);
        if (current_time >= project.maturity_date && project.redeemable != true){
            project.redeemable = true ;
        };
        
        event::emit(RedemptionFundsDeposited {
            project_id: object::uid_to_inner(&project.id),
            issuer: depositor,
            amount,
        });
    }

    // Buyer redeem bond token (burns the NFT)
    entry fun redeem_bond_token(
        project: &mut BondProject,
        token: BondToken,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let redeemer = tx_context::sender(ctx);
        
        // Verify ownership
        assert!(token.owner == redeemer, ENotTokenOwner);
        assert!(!token.is_redeemed, EBondAlreadyRedeemed);
        
        // Verify bond has matured 
        let current_time = clock::timestamp_ms(clock);
        assert!(current_time >= token.maturity_date, EBondNotMatured);
        
        // Calculate redemption amount (principal + interest)
        let principal = token.amount;
        
        // Calculate time held from purchase to maturity (in milliseconds)
        let time_held_ms = token.maturity_date - token.purchase_date;
        // Convert ms to day
        let time_held_days = time_held_ms / (1000 * 60 * 60 * 24);
        
        // Simple interest calculation using rate stored in token
        let interest = (principal * token.annual_interest_rate * time_held_days) / (365 * 10000);
        let redemption_amount = principal + interest;
        
        // Check redemption pool has enough funds
        let pool_balance = balance::value(&project.redemption_pool);
        assert!(pool_balance >= redemption_amount, EInsufficientRedemptionFunds);
        
        // Transfer redemption funds to token holder
        let redemption_balance = balance::split(&mut project.redemption_pool, redemption_amount);
        let redemption_coin = coin::from_balance(redemption_balance, ctx);
        transfer::public_transfer(redemption_coin, redeemer);
        
        // Update project state
        project.tokens_redeemed = project.tokens_redeemed + 1;
        project.amount_redeemed = project.amount_redeemed + principal;
        
        // Check if all amount are redeemed
        if (project.amount_redeemed >= project.amount_raised) {
            project.active = false;
        };
        
        let token_id = object::uid_to_inner(&token.id);
        let project_id = token.project_id;
        
        event::emit(BondTokenRedeemed {
            project_id,
            token_id,
            redeemer,
            redemption_amount,
        });
        
        // Burn the bond NFT
        let BondToken { 
            id, 
            project_id: _, 
            bond_name: _,
            token_image_url: _,
            token_number: _, 
            owner: _, 
            amount: _, 
            purchase_date: _, 
            maturity_date: _,
            annual_interest_rate: _,
            is_redeemed: _ 
        } = token;
        object::delete(id);
    }

    // Issuer withdraws raised funds
    entry fun withdraw_raised_funds(
        project: &mut BondProject,
        amount: u64,
        ctx: &mut TxContext
    ) {
        let withdrawer = tx_context::sender(ctx);
        assert!(project.issuer == withdrawer, ENotBondIssuer);
        assert!(amount > 0, EWithdrawAmountIsZero);
        
        let fund_balance = balance::value(&project.raised_funds);
        assert!(fund_balance >= amount, EInsufficientFunds);
        
        let withdrawn_balance = balance::split(&mut project.raised_funds, amount);
        let withdrawn_coin = coin::from_balance(withdrawn_balance, ctx);
        
        event::emit(FundsWithdrawn {
            project_id: object::uid_to_inner(&project.id),
            withdrawer,
            amount,
        });
        
        transfer::public_transfer(withdrawn_coin, withdrawer);
    }

    // Pause bond token sale
    entry fun pause_sale(
        project: &mut BondProject,
        ctx: &TxContext
    ) {
        let sender = tx_context::sender(ctx);
        assert!(project.issuer == sender, ENotBondIssuer);
        assert!(project.active, EInvalidParameter); // Can only pause if currently active
        
        project.active = false;
        
        event::emit(SalePaused {
            project_id: object::uid_to_inner(&project.id),
            paused_by: sender,
        });
    }

    // Resume bond token sale
    entry fun resume_sale(
        project: &mut BondProject,
        ctx: &TxContext
    ) {
        let sender = tx_context::sender(ctx);
        assert!(project.issuer == sender, ENotBondIssuer);
        assert!(!project.active, EInvalidParameter); // Can only resume if currently paused
        
        project.active = true;
        
        event::emit(SaleResumed {
            project_id: object::uid_to_inner(&project.id),
            resumed_by: sender,
        });
    }


    // --- Public view functions ---
    
    // Get bond project information
    public fun get_bond_project_info(project: &BondProject): (
        address,  // issuer
        String,   // issuer_name
        String,   // bond_name
        String,   // bond_image_url
        String,   // token_image_url
        String,   // metadata_url
        u64,      // total_amount (募集總額度)
        u64,      // amount_raised (已募集金額)
        u64,      // amount_redeemed (已贖回金額)
        u64,      // tokens_issued (已發行代幣數)
        u64,      // tokens_redeemed
        u64,      // annual_interest_rate
        u64,      // maturity_date
        u64,      // issue_date
        u64,      // raised_funds
        u64,      // redemption_pool
        bool,     // active_status
        bool,     // redeemable_status
    ) {
        return(
            project.issuer,
            project.issuer_name,
            project.bond_name,
            project.bond_image_url,
            project.token_image_url,
            project.metadata_url,
            project.total_amount,
            project.amount_raised,
            project.amount_redeemed,
            project.tokens_issued,
            project.tokens_redeemed,
            project.annual_interest_rate,
            project.maturity_date,
            project.issue_date,
            balance::value(&project.raised_funds),
            balance::value(&project.redemption_pool),
            project.active, 
            project.redeemable,
        )
    }

    // Get bond token information
    public fun get_bond_token_info(token: &BondToken): (
        ID, // project_id
        String, // bond_name
        String, // token_image_url
        u64, // token_number
        address, // owner
        u64, // amount (購買金額)
        u64, // purchase_date
        u64, // maturity_date
        u64, // annual_interest_rate
        bool // is_redeemed
    ) {
        return(
            token.project_id,
            token.bond_name,
            token.token_image_url,
            token.token_number,
            token.owner,
            token.amount,
            token.purchase_date,
            token.maturity_date,
            token.annual_interest_rate,
            token.is_redeemed
        )
    }

    // Get bond project ID
    public fun get_project_id(project: &BondProject): ID {
        object::uid_to_inner(&project.id)
    }

    // Get bond token ID
    public fun get_token_id(token: &BondToken): ID {
        object::uid_to_inner(&token.id)
    }

    // Get available capacity (remaining amount that can be raised)
    public fun get_available_capacity(project: &BondProject): u64 {
        project.total_amount - project.amount_raised
    }

    // Calculate redemption amount for a bond token (principal + interest)
    public fun calculate_redemption_amount(
        token: &BondToken,
        clock: &Clock
    ): u64 {
        let current_time = clock::timestamp_ms(clock);
        
        // Calculate time held from purchase to maturity (in milliseconds)
        let maturity_time = if (current_time >= token.maturity_date) {
            token.maturity_date
        } else {
            current_time
        };
        
        let time_held_ms = maturity_time - token.purchase_date;
        // Convert to days: ms -> seconds -> days
        let time_held_days = time_held_ms / (1000 * 60 * 60 * 24);
        
        let principal = token.amount;
        // Simple interest calculation using rate from token
        let interest = (principal * token.annual_interest_rate * time_held_days) / (365 * 10000);
        
        principal + interest
    }

    // Check if bond is currently redeemable
    public fun is_bond_redeemable(project: &BondProject, clock: &Clock): bool {
        let current_time = clock::timestamp_ms(clock);
        current_time >= project.maturity_date && project.redeemable
    }

    // Get sale progress (amount_raised, total_amount, percentage)
    public fun get_sale_progress(project: &BondProject): (u64, u64, u64) {
        let amount_raised = project.amount_raised;
        let total_amount = project.total_amount;
        let percentage = if (total_amount > 0) {
            (amount_raised * 100) / total_amount
        } else {
            0
        };
        (amount_raised, total_amount, percentage)
    }

    // Get total funds raised
    public fun get_total_raised(project: &BondProject): u64 {
        balance::value(&project.raised_funds)
    }

    // Get redemption pool balance
    public fun get_redemption_pool_balance(project: &BondProject): u64 {
        balance::value(&project.redemption_pool)
    }

    // Get number of tokens remaining to be redeemed
    public fun get_tokens_pending_redemption(project: &BondProject): u64 {
        project.tokens_issued - project.tokens_redeemed
    }
}

