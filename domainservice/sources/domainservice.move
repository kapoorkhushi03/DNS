module dns::domainservice {
    use sui::object::{Self, UID};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use sui::table::{Self, Table};
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use std::string::String;
    use sui::balance::{Self, Balance};
    use sui::event;

    // Error codes
    const EIPAlreadyExists: u64 = 0;
    const EIPNotFound: u64 = 1;
    const EDomainAlreadyExists: u64 = 2;
    const EDomainNotFound: u64 = 3;
    const EInsufficientFunds: u64 = 4;
    const ENotDomainOwner: u64 = 5;

    // Domain price in SUI (fixed for now)
    const DOMAIN_PRICE: u64 = 1_000_000_000; // 1 SUI

    // Struct to represent an IP address record
    struct IPRecord has store {
        ip_address: String,
        website_code: String,
        owner: address,
    }

    // Struct to represent a domain record
    struct DomainRecord has store {
        domain_name: String,
        ip_address: String,
        owner: address,
    }

    // Shared object for the IP registry
    struct IPRegistry has key {
        id: UID,
        ips: Table<String, IPRecord>,
    }

    // Shared object for the Domain registry
    struct DomainRegistry has key {
        id: UID,
        domains: Table<String, DomainRecord>,
        fee_balance: Balance<SUI>,
    }

    // Events
    struct IPAllotted has copy, drop {
        ip_address: String,
        owner: address,
    }

    struct DomainAssigned has copy, drop {
        domain_name: String,
        ip_address: String,
        owner: address,
    }

    struct DomainPurchased has copy, drop {
        domain_name: String,
        new_owner: address,
        price: u64,
    }

    // === Initialization ===

    fun init(ctx: &mut TxContext) {
        let ip_registry = IPRegistry {
            id: object::new(ctx),
            ips: table::new(ctx),
        };

        let domain_registry = DomainRegistry {
            id: object::new(ctx),
            domains: table::new(ctx),
            fee_balance: balance::zero(),
        };

        transfer::share_object(ip_registry);
        transfer::share_object(domain_registry);
    }

    // === IP Registry Functions ===

    public entry fun allot_ip(
        ip_registry: &mut IPRegistry,
        ip_address: String,
        website_code: String,
        owner: address,
        ctx: &mut TxContext
    ) {
        // Check if IP already exists
        assert!(!table::contains(&ip_registry.ips, ip_address), EIPAlreadyExists);

        // Create new IP record
        let ip_record = IPRecord {
            ip_address: ip_address,
            website_code: website_code,
            owner: owner,
        };

        // Store IP record in registry
        table::add(&mut ip_registry.ips, ip_address, ip_record);

        // Emit event
        event::emit(IPAllotted {
            ip_address: ip_address,
            owner: owner,
        });
    }

    public fun read_ip(ip_registry: &IPRegistry, ip_address: String): (address, String) {
        assert!(table::contains(&ip_registry.ips, ip_address), EIPNotFound);
        
        let ip_record = table::borrow(&ip_registry.ips, ip_address);
        (ip_record.owner, ip_record.website_code)
    }

    // === Domain Registry Functions ===

    public entry fun assign_domain(
        ip_registry: &mut IPRegistry,
        domain_registry: &mut DomainRegistry,
        domain_name: String,
        ip_address: String,
        website_code: String,
        owner: address,
        ctx: &mut TxContext
    ) {
        // Check if domain already exists
        assert!(!table::contains(&domain_registry.domains, domain_name), EDomainAlreadyExists);

        // Create IP if it doesn't exist
        if (!table::contains(&ip_registry.ips, ip_address)) {
            allot_ip(ip_registry, ip_address, website_code, owner, ctx);
        };

        // Create domain record
        let domain_record = DomainRecord {
            domain_name: domain_name,
            ip_address: ip_address,
            owner: owner,
        };

        // Store domain record in registry
        table::add(&mut domain_registry.domains, domain_name, domain_record);

        // Emit event
        event::emit(DomainAssigned {
            domain_name: domain_name,
            ip_address: ip_address,
            owner: owner,
        });
    }

    public fun read_domain(
        ip_registry: &IPRegistry,
        domain_registry: &DomainRegistry,
        domain_name: String
    ): (address, String) {
        assert!(table::contains(&domain_registry.domains, domain_name), EDomainNotFound);
        
        let domain_record = table::borrow(&domain_registry.domains, domain_name);
        
        // Call read_ip with the ip_address from the domain record
        read_ip(ip_registry, domain_record.ip_address)
    }

    public fun check_domain(domain_registry: &DomainRegistry, domain_name: String): bool {
        table::contains(&domain_registry.domains, domain_name)
    }

    // === Transaction Functions ===

    public entry fun buy_domain(
        domain_registry: &mut DomainRegistry,
        domain_name: String,
        payment: Coin<SUI>,
        ctx: &mut TxContext
    ) {
        // Check if domain exists
        assert!(table::contains(&domain_registry.domains, domain_name), EDomainNotFound);
        
        // Check if payment is sufficient
        let payment_value = coin::value(&payment);
        assert!(payment_value >= DOMAIN_PRICE, EInsufficientFunds);
        
        // Extract the required payment
        let paid = coin::split(&mut payment, DOMAIN_PRICE, ctx);
        
        // Add payment to fee balance
        let paid_balance = coin::into_balance(paid);
        balance::join(&mut domain_registry.fee_balance, paid_balance);
        
        // Return any remaining funds
        if (coin::value(&payment) > 0) {
            transfer::public_transfer(payment, tx_context::sender(ctx));
        } else {
            coin::destroy_zero(payment);
        };
        
        // Update domain ownership
        let domain_record = table::borrow_mut(&mut domain_registry.domains, domain_name);
        domain_record.owner = tx_context::sender(ctx);
        
        // Emit event
        event::emit(DomainPurchased {
            domain_name: domain_name,
            new_owner: tx_context::sender(ctx),
            price: DOMAIN_PRICE,
        });
    }

    // Function to transfer domain ownership
    public entry fun transfer_domain(
        domain_registry: &mut DomainRegistry,
        domain_name: String,
        new_owner: address,
        ctx: &mut TxContext
    ) {
        // Check if domain exists
        assert!(table::contains(&domain_registry.domains, domain_name), EDomainNotFound);
        
        // Get the domain record
        let domain_record = table::borrow_mut(&mut domain_registry.domains, domain_name);
        
        // Check if sender is the owner
        assert!(domain_record.owner == tx_context::sender(ctx), ENotDomainOwner);
        
        // Update domain ownership
        domain_record.owner = new_owner;
    }

    // === Admin Functions ===

    // Withdraw collected fees (would typically have access control)
    public entry fun withdraw_fees(
        domain_registry: &mut DomainRegistry,
        amount: u64,
        recipient: address,
        ctx: &mut TxContext
    ) {
        let current_balance = balance::value(&domain_registry.fee_balance);
        assert!(current_balance >= amount, EInsufficientFunds);
        
        let withdrawn = coin::from_balance(balance::split(&mut domain_registry.fee_balance, amount), ctx);
        transfer::public_transfer(withdrawn, recipient);
    }
}