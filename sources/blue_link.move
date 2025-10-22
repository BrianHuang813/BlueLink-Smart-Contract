module blue_link::blue_link {

    use sui::coin::{Self, Coin};
    use sui::balance::{Self, Balance};
    use sui::event;
    use sui::sui::SUI; // will use USDC or self-minted coin as currency.
    use std::string::{Self, String};

    
    // --- Error codes ---
    // General errors
    const EInvalidAmount: u64 = 100; // Invalid amount
    const EInvalidParameter: u64 = 101; // Invalid parameter

    // Purchase related errors (2xx)
    const EInsufficientPayment: u64 = 201; // Payment is insufficient
    const EPurchaseAmountIsZero: u64 = 202; // Purchase amount must be greater than zero
    const EInsufficientTokensAvailable: u64 = 204; // Not enough tokens available
    
    // Bond management errors (3xx)
    const ENotBondIssuer: u64 = 300; // Only bond issuer can perform this action
    const EInsufficientFunds: u64 = 301; // Insufficient funds
    const EWithdrawAmountIsZero: u64 = 302; // Withdrawal amount must be greater than zero
    
    // Redemption related errors (4xx)
    const EBondNotMatured: u64 = 400; // Bond has not matured yet
    const ENotTokenOwner: u64 = 401; // Only token owner can redeem
    const EInsufficientRedemptionFunds: u64 = 402; // Insufficient redemption funds
    const EBondAlreadyRedeemed: u64 = 403; // Bond token already redeemed


    // --- Struct definitions ---
    // Bond project - represents a tokenized bond
    public struct BondProject has key, store {
        id: UID,
        issuer: address, // Bond issuer
        issuer_name: String,
        bond_name: String,
        total_supply: u64, // Total number of bond tokens
        price: u64, // Price per token in USD stable coin
        tokens_sold: u64, // Number of tokens sold
        tokens_redeemed: u64, // Number of tokens redeemed
        annual_interest_rate: u64, // Annual interest rate in basis points (e.g., 500 = 5%)
        maturity_date: u64, // Unix timestamp of maturity date
        issue_date: u64, // Unix timestamp of issue date
        active: bool, // Bond status (active / closed)
        redeemable: bool, // Whether bond is redeemable
        raised_funds: Balance<SUI>, // Funds raised from token sales
        redemption_pool: Balance<SUI>, // Pool for redemption (principal + interest)
    }

    // Bond token NFT - represents ownership of a portion of the bond
    public struct BondToken has key, store {
        id: UID,
        project_id: ID, // Associated bond project
        token_number: u64, // Sequential token number
        owner: address, // Token owner
        price: u64, // Price paid for this token
        purchase_date: u64, // Unix timestamp of purchase
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
        quantity: u64,
        total_amount: u64,
        token_ids: vector<ID>,
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


    // --- Entry Functions ---
    
    // Create a new bond project
    entry fun create_bond_project(
        issuer_name: vector<u8>,
        bond_name: vector<u8>,
        total_supply: u64,
        price: u64,
        annual_interest_rate: u64, // in basis points
        maturity_date: u64, // Unix timestamp
        ctx: &mut TxContext
    ) {
        assert!(total_supply > 0, EInvalidParameter);
        assert!(price > 0, EInvalidParameter);
        
        let issuer = tx_context::sender(ctx);
        let project_id = object::new(ctx);
        let project_id_copy = object::uid_to_inner(&project_id);
        let issue_date = tx_context::epoch(ctx);
        
        let project = BondProject {
            id: project_id,
            issuer,
            issuer_name: string::utf8(issuer_name),
            bond_name: string::utf8(bond_name),
            total_supply,
            price,
            tokens_sold: 0,
            tokens_redeemed: 0,
            annual_interest_rate,
            maturity_date,
            issue_date,
            active: true,
            redeemable: false,
            raised_funds: balance::zero<SUI>(),
            redemption_pool: balance::zero<SUI>(),
        };

        event::emit(BondProjectCreated {
            id: project_id_copy,
            issuer,
            bond_name: project.bond_name,
            total_supply,
            price,
            annual_interest_rate,
            maturity_date,
        });

        transfer::public_transfer(project, issuer);
    }

    // Buy bond tokens
    entry fun buy_bond_rwa_tokens(
        project: &mut BondProject,
        quantity: u64,
        payment: Coin<SUI>,
        ctx: &mut TxContext
    ) {
        assert!(quantity > 0, EPurchaseAmountIsZero);
        
        // Check if enough tokens are available
        let available_tokens = project.total_supply - project.tokens_sold;
        assert!(available_tokens >= quantity, EInsufficientTokensAvailable);
        
        // Calculate required payment
        let required_amount = project.price * quantity;
        let payment_amount = coin::value(&payment);
        assert!(payment_amount >= required_amount, EInsufficientPayment);
        
        let buyer = tx_context::sender(ctx);
        let project_id = object::uid_to_inner(&project.id);
        let purchase_date = tx_context::epoch(ctx);
        
        // Add payment to raised funds
        let payment_balance = coin::into_balance(payment);
        balance::join(&mut project.raised_funds, payment_balance);
        
        // Create bond tokens
        let mut token_ids = vector::empty<ID>();
        let mut i = 0;
        while (i < quantity) {
            let token_id = object::new(ctx);
            let token_id_copy = object::uid_to_inner(&token_id);
            vector::push_back(&mut token_ids, token_id_copy);
            
            let token = BondToken {
                id: token_id,
                project_id,
                token_number: project.tokens_sold + i + 1,
                owner: buyer,
                price: project.price,
                purchase_date,
                is_redeemed: false,
            };
            
            transfer::public_transfer(token, buyer);
            i = i + 1;
        };
        
        // Update project state
        project.tokens_sold = project.tokens_sold + quantity;
        
        event::emit(BondTokensPurchased {
            project_id,
            buyer,
            quantity,
            total_amount: required_amount,
            token_ids,
        });
    }

    // Issuer deposits redemption funds (principal + interest)
    entry fun deposit_redemption_funds(
        project: &mut BondProject,
        payment: Coin<SUI>,
        ctx: &TxContext
    ) {
        let depositor = tx_context::sender(ctx);
        assert!(project.issuer == depositor, ENotBondIssuer);
        
        let amount = coin::value(&payment);
        assert!(amount > 0, EInvalidAmount);
        
        let payment_balance = coin::into_balance(payment);
        balance::join(&mut project.redemption_pool, payment_balance);
        
        // Update status to redeemable if maturity date is reached
        let current_time = tx_context::epoch(ctx);
        if (current_time >= project.maturity_date && project.redeemable != true){
            project.redeemable = true ;
        };
        
        event::emit(RedemptionFundsDeposited {
            project_id: object::uid_to_inner(&project.id),
            issuer: depositor,
            amount,
        });
    }

    // Redeem bond token (burns the NFT)
    entry fun redeem_bond_token(
        project: &mut BondProject,
        token: BondToken,
        ctx: &mut TxContext
    ) {
        let redeemer = tx_context::sender(ctx);
        
        // Verify ownership
        assert!(token.owner == redeemer, ENotTokenOwner);
        assert!(!token.is_redeemed, EBondAlreadyRedeemed);
        
        // Verify bond has matured
        let current_time = tx_context::epoch(ctx);
        assert!(current_time >= project.maturity_date, EBondNotMatured);
        
        // Calculate redemption amount (principal + interest)
        let principal = token.price;
        let time_held = if (current_time > project.maturity_date) {
            project.maturity_date - token.purchase_date
        } else {
            current_time - token.purchase_date
        };
        
        // Simple interest calculation: principal * rate * time / (365 * 10000)
        // Assuming time is in days and rate is in basis points
        let interest = (principal * project.annual_interest_rate * time_held) / (365 * 10000);
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
        
        // Check if all tokens are redeemed
        if (project.tokens_redeemed == project.tokens_sold) {
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
        let BondToken { id, project_id: _, token_number: _, owner: _, price: _, purchase_date: _, is_redeemed: _ } = token;
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


    // --- Public view functions ---
    
    // Get bond project information
    public fun get_bond_project_info(project: &BondProject): (
        String, // bond_name
        address, // issuer
        u64, // total_supply
        u64, // token_price
        u64, // tokens_sold
        u64, // tokens_redeemed
        u64, // annual_interest_rate
        u64, // maturity_date
        u64, // raised_funds
        u64, // redemption_pool
        bool,  // active_status
        bool,  // redeemable_status
    ) {
        return(
            project.bond_name,
            project.issuer,
            project.total_supply,
            project.price,
            project.tokens_sold,
            project.tokens_redeemed,
            project.annual_interest_rate,
            project.maturity_date,
            balance::value(&project.raised_funds),
            balance::value(&project.redemption_pool),
            project.active, 
            project.redeemable,
        )
    }

    // Get bond token information
    public fun get_bond_token_info(token: &BondToken): (
        ID, // project_id
        u64, // token_number
        address, // owner
        u64, // purchase_price
        u64, // purchase_date
        bool // is_redeemed
    ) {
        return(
            token.project_id,
            token.token_number,
            token.owner,
            token.price,
            token.purchase_date,
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

    // Get available tokens for sale
    public fun get_available_tokens(project: &BondProject): u64 {
        project.total_supply - project.tokens_sold
    }
}


