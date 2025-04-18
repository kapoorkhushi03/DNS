#[test_only]
module domain_service::domain_service_tests {
    use domain_service::domain_service::{Self, DomainRegistry};
    use sui::test_scenario::{Self as ts, Scenario};
    use std::string::{Self, String};
    use sui::vec_map;
    
    // Test addresses
    const ADMIN: address = @0xAD;
    const USER1: address = @0x1;
    const USER2: address = @0x2;
    
    // Test error codes
    const EDomainAlreadyExists: u64 = 0;
    const EDomainNotFound: u64 = 1;
    const ENotDomainOwner: u64 = 2;
    
    // Helper function to create a test scenario and initialize the domain registry
    fun setup(): Scenario {
        let scenario = ts::begin(ADMIN);
        {
            domain_service::init(ts::ctx(&mut scenario));
        };
        scenario
    }
    
    #[test]
    fun test_create_domain() {
        let scenario = setup();
        
        // Create a domain as USER1
        ts::next_tx(&mut scenario, USER1);
        {
            let registry = ts::take_shared<DomainRegistry>(&scenario);
            domain_service::create_domain(
                &mut registry,
                b"example.com",
                b"192.168.1.1",
                ts::ctx(&mut scenario)
            );
            
            // Verify domain record
            let a_record = domain_service::domain_lookup(&registry, b"example.com");
            assert!(a_record == string::utf8(b"192.168.1.1"), 0);
            
            ts::return_shared(registry);
        };
        
        ts::end(scenario);
    }
    
    #[test]
    #[expected_failure(abort_code = EDomainAlreadyExists)]
    fun test_create_duplicate_domain() {
        let scenario = setup();
        
        // Create a domain
        ts::next_tx(&mut scenario, USER1);
        {
            let registry = ts::take_shared<DomainRegistry>(&scenario);
            domain_service::create_domain(
                &mut registry,
                b"example.com",
                b"192.168.1.1",
                ts::ctx(&mut scenario)
            );
            ts::return_shared(registry);
        };
        
        // Try to create the same domain again (should fail)
        ts::next_tx(&mut scenario, USER1);
        {
            let registry = ts::take_shared<DomainRegistry>(&scenario);
            domain_service::create_domain(
                &mut registry,
                b"example.com",
                b"192.168.1.2",
                ts::ctx(&mut scenario)
            );
            ts::return_shared(registry);
        };
        
        ts::end(scenario);
    }
    
    #[test]
    fun test_update_domain() {
        let scenario = setup();
        
        // Create a domain
        ts::next_tx(&mut scenario, USER1);
        {
            let registry = ts::take_shared<DomainRegistry>(&scenario);
            domain_service::create_domain(
                &mut registry,
                b"example.com",
                b"192.168.1.1",
                ts::ctx(&mut scenario)
            );
            ts::return_shared(registry);
        };
        
        // Update the domain
        ts::next_tx(&mut scenario, USER1);
        {
            let registry = ts::take_shared<DomainRegistry>(&scenario);
            domain_service::update_domain(
                &mut registry,
                b"example.com",
                b"192.168.1.2",
                ts::ctx(&mut scenario)
            );
            
            // Verify updated record
            let a_record = domain_service::domain_lookup(&registry, b"example.com");
            assert!(a_record == string::utf8(b"192.168.1.2"), 0);
            
            ts::return_shared(registry);
        };
        
        ts::end(scenario);
    }
    
    #[test]
    #[expected_failure(abort_code = ENotDomainOwner)]
    fun test_update_domain_not_owner() {
        let scenario = setup();
        
        // Create a domain as USER1
        ts::next_tx(&mut scenario, USER1);
        {
            let registry = ts::take_shared<DomainRegistry>(&scenario);
            domain_service::create_domain(
                &mut registry,
                b"example.com",
                b"192.168.1.1",
                ts::ctx(&mut scenario)
            );
            ts::return_shared(registry);
        };
        
        // Try to update the domain as USER2 (should fail)
        ts::next_tx(&mut scenario, USER2);
        {
            let registry = ts::take_shared<DomainRegistry>(&scenario);
            domain_service::update_domain(
                &mut registry,
                b"example.com",
                b"192.168.1.2",
                ts::ctx(&mut scenario)
            );
            ts::return_shared(registry);
        };
        
        ts::end(scenario);
    }
    
    #[test]
    fun test_delete_domain() {
        let scenario = setup();
        
        // Create a domain
        ts::next_tx(&mut scenario, USER1);
        {
            let registry = ts::take_shared<DomainRegistry>(&scenario);
            domain_service::create_domain(
                &mut registry,
                b"example.com",
                b"192.168.1.1",
                ts::ctx(&mut scenario)
            );
            ts::return_shared(registry);
        };
        
        // Delete the domain
        ts::next_tx(&mut scenario, USER1);
        {
            let registry = ts::take_shared<DomainRegistry>(&scenario);
            domain_service::delete_domain(
                &mut registry,
                b"example.com",
                ts::ctx(&mut scenario)
            );
            ts::return_shared(registry);
        };
        
        // Verify domain is deleted (should fail to look it up)
        ts::next_tx(&mut scenario, USER1);
        {
            let registry = ts::take_shared<DomainRegistry>(&scenario);
            
            // We can't directly test for failure in the positive test case,
            // but in a real scenario this would fail with EDomainNotFound
            let owner_domains = domain_service::get_all_domains_by_owner(&registry, USER1);
            assert!(vec_map::is_empty(&owner_domains), 0);
            
            ts::return_shared(registry);
        };
        
        ts::end(scenario);
    }
    
    #[test]
    #[expected_failure(abort_code = ENotDomainOwner)]
    fun test_delete_domain_not_owner() {
        let scenario = setup();
        
        // Create a domain as USER1
        ts::next_tx(&mut scenario, USER1);
        {
            let registry = ts::take_shared<DomainRegistry>(&scenario);
            domain_service::create_domain(
                &mut registry,
                b"example.com",
                b"192.168.1.1",
                ts::ctx(&mut scenario)
            );
            ts::return_shared(registry);
        };
        
        // Try to delete the domain as USER2 (should fail)
        ts::next_tx(&mut scenario, USER2);
        {
            let registry = ts::take_shared<DomainRegistry>(&scenario);
            domain_service::delete_domain(
                &mut registry,
                b"example.com",
                ts::ctx(&mut scenario)
            );
            ts::return_shared(registry);
        };
        
        ts::end(scenario);
    }
    
    #[test]
    fun test_get_all_domains_by_owner() {
        let scenario = setup();
        
        // Create multiple domains for USER1
        ts::next_tx(&mut scenario, USER1);
        {
            let registry = ts::take_shared<DomainRegistry>(&scenario);
            domain_service::create_domain(
                &mut registry,
                b"example1.com",
                b"192.168.1.1",
                ts::ctx(&mut scenario)
            );
            domain_service::create_domain(
                &mut registry,
                b"example2.com",
                b"192.168.1.2",
                ts::ctx(&mut scenario)
            );
            ts::return_shared(registry);
        };
        
        // Create a domain for USER2
        ts::next_tx(&mut scenario, USER2);
        {
            let registry = ts::take_shared<DomainRegistry>(&scenario);
            domain_service::create_domain(
                &mut registry,
                b"user2-domain.com",
                b"192.168.2.1",
                ts::ctx(&mut scenario)
            );
            ts::return_shared(registry);
        };
        
        // Get domains for USER1
        ts::next_tx(&mut scenario, USER1);
        {
            let registry = ts::take_shared<DomainRegistry>(&scenario);
            let owner_domains = domain_service::get_all_domains_by_owner(&registry, USER1);
            
            // Verify USER1 has 2 domains
            assert!(vec_map::size(&owner_domains) == 2, 0);
            
            ts::return_shared(registry);
        };
        
        ts::end(scenario);
    }
}