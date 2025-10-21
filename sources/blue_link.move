module blue_link::blue_link {

    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use sui::balance::{Self, Balance};
    use sui::event;
    use std::string::{Self, String};

    // --- Error codes ---
    // General errors

    // Donation related errors (2xx)
    const EDonorInsufficientBalance: u64 = 201; // Donor's balance is insufficient
    const EDonationAmountIsZero: u64 = 202; // Donation amount must be greater than zero
    
    // Withdrawal related errors (3xx)
    const ENotProjectCreator: u64 = 300; // Only project creator can withdraw funds
    const EProjectInsufficientFunds: u64 = 301; // Insufficient funds to withdraw
    const EWithdrawAmountIsZero: u64 = 302; // Withdrawal amount must be greater than zero


    // --- Struct definitions ---
    // Donation project
    public struct Project has key, store {
        id: UID,
        creator: address,
        creator_name: String,
        name: String,
        description: String,
        funding_goal: u64,
        total_raised: Balance<SUI>,
        donor_count: u64,
    }

    // Project created event
    public struct ProjectCreated has copy, drop {
        project_id: ID,
        creator: address,
        name: String,
        funding_goal: u64,
    }

    // Donation receipt NFT
    public struct DonationReceipt has key, store {
        id: UID,
        project_id: ID, // associated project
        donor: address, // donor's address
        amount: u64, // amount donated
    }

    // Donation made event
    public struct DonationMade has copy, drop {
        project_id: ID,
        donor: address,
        amount: u64,
        receipt_id: ID,
    }

    public struct FundsWithdrawn has copy, drop {
        project_id: ID,
        withdrawer: address,
        amount: u64,
    }

    // A entry func of listing available donation projects on the platform
    entry fun create_bond(name: vector<u8>, description: vector<u8>, funding_goal: u64, ctx: &mut TxContext){
        
        let creator = tx_context::sender(ctx); // Project creator(NGO / Government)
        let project_id = object::new(ctx); // Unique project ID
        let project_id_copy = object::uid_to_inner(&project_id);
        
        // Create a new project object
        let project = Project {
            id: project_id,
            creator,
            creator_name: string::utf8(name),
            name: string::utf8(name),
            description: string::utf8(description),
            funding_goal,
            total_raised: balance::zero<SUI>(),
            donor_count: 0,
        };

        // Broadcast project creation event
        event::emit(ProjectCreated {
            project_id: project_id_copy,
            creator,
            name: project.name,
            funding_goal,
        });

        transfer::public_transfer(project, creator);
    }

    entry fun donate(project: &mut Project, payment: Coin<SUI>, ctx: &mut TxContext){
        let amount = coin::value(&payment);
        assert!(amount > 0, EDonationAmountIsZero);

        let donor = tx_context::sender(ctx);
        let project_id = object::uid_to_inner(&project.id);
        
        // Add the payment to the project's balance
        let payment_balance = coin::into_balance(payment);
        balance::join(&mut project.total_raised, payment_balance);
        
        // Increment donor count
        project.donor_count = project.donor_count + 1;

        // Create donation receipt NFT
        let receipt_id = object::new(ctx);
        let receipt_id_copy = object::uid_to_inner(&receipt_id);
        
        let receipt = DonationReceipt {
            id: receipt_id,
            project_id,
            donor,
            amount,
        };

        event::emit(DonationMade {
            project_id,
            donor,
            amount,
            receipt_id: receipt_id_copy,
        });

        transfer::public_transfer(receipt, donor);
    }

    entry fun withdraw(project: &mut Project, ctx: &mut TxContext){

        let withdrawer = tx_context::sender(ctx); // Withdraw transaction sender
        assert!(project.creator == withdrawer, ENotProjectCreator); // Only the project creator can withdraw funds

        let fund_balance = balance::value(&project.total_raised); 
        assert!(fund_balance > 0, EProjectInsufficientFunds); // Ensure there are enough funds to withdraw

        let withdrawn_balance = balance::split(&mut project.total_raised, fund_balance); // total_raised is a balance type
        let withdrawn_coin = coin::from_balance(withdrawn_balance, ctx); // Convert balance back to coin for transfer
        
        let project_id = object::uid_to_inner(&project.id);
        
        event::emit(FundsWithdrawn {
            project_id,
            withdrawer,
            amount: fund_balance,
        });

        transfer::public_transfer(withdrawn_coin, withdrawer);
    }

    // --- Public view functions ---
    // Return project details tuple
    public fun get_project_info(project: &Project): (String, String, u64, u64, u64, address){
        (
            project.name,
            project.description,
            project.funding_goal,
            balance::value(&project.total_raised),
            project.donor_count,
            project.creator
        )
    }

    public fun get_donation_receipt_info(receipt: &DonationReceipt): (ID, address, u64) {
        (receipt.project_id, receipt.donor, receipt.amount)
    }

    public fun get_project_id(project: &Project): ID {
        object::uid_to_inner(&project.id)
    }

    public fun get_receipt_id(receipt: &DonationReceipt): ID {
        object::uid_to_inner(&receipt.id)
    }
}



