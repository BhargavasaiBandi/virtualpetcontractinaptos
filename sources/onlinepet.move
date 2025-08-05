module pet_addr::virtual_pet {
    use std::string::{Self, String};
    use std::signer;
    use std::vector;
    use aptos_framework::timestamp;
    use aptos_framework::event::{Self, EventHandle};
    use aptos_framework::account;

    // Error codes
    const E_PET_NOT_EXISTS: u64 = 1;
    const E_PET_ALREADY_EXISTS: u64 = 2;
    const E_NOT_HUNGRY: u64 = 3;
    const E_CANNOT_EVOLVE: u64 = 4;
    const E_PET_DEAD: u64 = 5;

    // Pet stages
    const STAGE_EGG: u8 = 0;
    const STAGE_BABY: u8 = 1;
    const STAGE_ADULT: u8 = 2;
    const STAGE_ELDER: u8 = 3;

    // Pet status
    const STATUS_ALIVE: u8 = 1;
    const STATUS_DEAD: u8 = 0;

    // Time constants (in seconds)
    const HUNGER_INTERVAL: u64 = 3600; // 1 hour
    const EVOLUTION_TIME: u64 = 86400; // 24 hours
    const DEATH_TIME: u64 = 172800; // 48 hours without feeding

    struct Pet has key, store {
        name: String,
        pet_type: String,
        stage: u8,
        happiness: u64,
        hunger_level: u64,
        last_fed: u64,
        birth_time: u64,
        status: u8,
        evolution_points: u64,
    }

    struct PetStore has key {
        pets: vector<Pet>,
        pet_created_events: EventHandle<PetCreatedEvent>,
        pet_fed_events: EventHandle<PetFedEvent>,
        pet_evolved_events: EventHandle<PetEvolvedEvent>,
    }

    struct PetCreatedEvent has drop, store {
        owner: address,
        pet_name: String,
        pet_type: String,
        timestamp: u64,
    }

    struct PetFedEvent has drop, store {
        owner: address,
        pet_name: String,
        new_happiness: u64,
        timestamp: u64,
    }

    struct PetEvolvedEvent has drop, store {
        owner: address,
        pet_name: String,
        old_stage: u8,
        new_stage: u8,
        timestamp: u64,
    }

    // Initialize pet store for new users
    fun init_pet_store(account: &signer) {
        let pet_store = PetStore {
            pets: vector::empty<Pet>(),
            pet_created_events: account::new_event_handle<PetCreatedEvent>(account),
            pet_fed_events: account::new_event_handle<PetFedEvent>(account),
            pet_evolved_events: account::new_event_handle<PetEvolvedEvent>(account),
        };
        move_to(account, pet_store);
    }

    // Create a new pet
    public entry fun create_pet(
        account: &signer,
        name: String,
        pet_type: String
    ) acquires PetStore {
        let owner = signer::address_of(account);
        let current_time = timestamp::now_seconds();

        // Initialize pet store if it doesn't exist
        if (!exists<PetStore>(owner)) {
            init_pet_store(account);
        };

        let pet_store = borrow_global_mut<PetStore>(owner);
        
        // Check if pet with same name already exists
        let i = 0;
        let len = vector::length(&pet_store.pets);
        while (i < len) {
            let pet = vector::borrow(&pet_store.pets, i);
            assert!(pet.name != name, E_PET_ALREADY_EXISTS);
            i = i + 1;
        };

        let new_pet = Pet {
            name: name,
            pet_type: pet_type,
            stage: STAGE_EGG,
            happiness: 50,
            hunger_level: 50,
            last_fed: current_time,
            birth_time: current_time,
            status: STATUS_ALIVE,
            evolution_points: 0,
        };

        vector::push_back(&mut pet_store.pets, new_pet);

        // Emit event
        event::emit_event(&mut pet_store.pet_created_events, PetCreatedEvent {
            owner,
            pet_name: name,
            pet_type: pet_type,
            timestamp: current_time,
        });
    }

    // Feed a pet
    public entry fun feed_pet(
        account: &signer,
        pet_name: String
    ) acquires PetStore {
        let owner = signer::address_of(account);
        assert!(exists<PetStore>(owner), E_PET_NOT_EXISTS);
        
        let pet_store = borrow_global_mut<PetStore>(owner);
        let current_time = timestamp::now_seconds();
        
        let pet_index = find_pet_index(&pet_store.pets, &pet_name);
        let pet = vector::borrow_mut(&mut pet_store.pets, pet_index);
        
        // Check if pet is alive
        assert!(pet.status == STATUS_ALIVE, E_PET_DEAD);
        
        // Update pet stats
        pet.hunger_level = 100;
        pet.happiness = if (pet.happiness + 20 > 100) { 100 } else { pet.happiness + 20 };
        pet.last_fed = current_time;
        pet.evolution_points = pet.evolution_points + 10;

        // Emit event
        event::emit_event(&mut pet_store.pet_fed_events, PetFedEvent {
            owner,
            pet_name: pet_name,
            new_happiness: pet.happiness,
            timestamp: current_time,
        });
    }

    // Evolve pet to next stage
    public entry fun evolve_pet(
        account: &signer,
        pet_name: String
    ) acquires PetStore {
        let owner = signer::address_of(account);
        assert!(exists<PetStore>(owner), E_PET_NOT_EXISTS);
        
        let pet_store = borrow_global_mut<PetStore>(owner);
        let current_time = timestamp::now_seconds();
        
        let pet_index = find_pet_index(&pet_store.pets, &pet_name);
        let pet = vector::borrow_mut(&mut pet_store.pets, pet_index);
        
        // Check if pet is alive
        assert!(pet.status == STATUS_ALIVE, E_PET_DEAD);
        
        let old_stage = pet.stage;
        let can_evolve = false;
        
        // Evolution conditions
        if (pet.stage == STAGE_EGG && current_time >= pet.birth_time + EVOLUTION_TIME) {
            pet.stage = STAGE_BABY;
            can_evolve = true;
        } else if (pet.stage == STAGE_BABY && pet.evolution_points >= 100) {
            pet.stage = STAGE_ADULT;
            can_evolve = true;
        } else if (pet.stage == STAGE_ADULT && pet.evolution_points >= 500 && pet.happiness >= 80) {
            pet.stage = STAGE_ELDER;
            can_evolve = true;
        };
        
        assert!(can_evolve, E_CANNOT_EVOLVE);

        // Reset evolution points after evolution
        pet.evolution_points = 0;

        // Emit event
        event::emit_event(&mut pet_store.pet_evolved_events, PetEvolvedEvent {
            owner,
            pet_name: pet_name,
            old_stage,
            new_stage: pet.stage,
            timestamp: current_time,
        });
    }

    // Update pet status (called periodically)
    public entry fun update_pet_status(
        account: &signer,
        pet_name: String
    ) acquires PetStore {
        let owner = signer::address_of(account);
        assert!(exists<PetStore>(owner), E_PET_NOT_EXISTS);
        
        let pet_store = borrow_global_mut<PetStore>(owner);
        let current_time = timestamp::now_seconds();
        
        let pet_index = find_pet_index(&pet_store.pets, &pet_name);
        let pet = vector::borrow_mut(&mut pet_store.pets, pet_index);
        
        // Check if pet died from neglect
        if (current_time >= pet.last_fed + DEATH_TIME) {
            pet.status = STATUS_DEAD;
            pet.happiness = 0;
            pet.hunger_level = 0;
        } else {
            // Decrease hunger and happiness over time
            let time_diff = current_time - pet.last_fed;
            let hunger_decrease = (time_diff / HUNGER_INTERVAL) * 10;
            let happiness_decrease = (time_diff / HUNGER_INTERVAL) * 5;
            
            pet.hunger_level = if (hunger_decrease > pet.hunger_level) { 0 } else { pet.hunger_level - hunger_decrease };
            pet.happiness = if (happiness_decrease > pet.happiness) { 0 } else { pet.happiness - happiness_decrease };
        };
    }

    // Helper function to find pet index
    fun find_pet_index(pets: &vector<Pet>, pet_name: &String): u64 {
        let i = 0;
        let len = vector::length(pets);
        while (i < len) {
            let pet = vector::borrow(pets, i);
            if (pet.name == *pet_name) {
                return i
            };
            i = i + 1;
        };
        abort E_PET_NOT_EXISTS
    }

    // View functions
    #[view]
    public fun get_pet_info(owner: address, pet_name: String): (String, String, u8, u64, u64, u64, u8, u64) acquires PetStore {
        assert!(exists<PetStore>(owner), E_PET_NOT_EXISTS);
        let pet_store = borrow_global<PetStore>(owner);
        
        let pet_index = find_pet_index(&pet_store.pets, &pet_name);
        let pet = vector::borrow(&pet_store.pets, pet_index);
        
        (pet.name, pet.pet_type, pet.stage, pet.happiness, pet.hunger_level, pet.evolution_points, pet.status, pet.birth_time)
    }

    #[view]
    public fun get_all_pets(owner: address): vector<String> acquires PetStore {
        if (!exists<PetStore>(owner)) {
            return vector::empty<String>()
        };
        
        let pet_store = borrow_global<PetStore>(owner);
        let pet_names = vector::empty<String>();
        let i = 0;
        let len = vector::length(&pet_store.pets);
        
        while (i < len) {
            let pet = vector::borrow(&pet_store.pets, i);
            vector::push_back(&mut pet_names, pet.name);
            i = i + 1;
        };
        
        pet_names
    }

    #[view]
    public fun get_pet_stage_name(stage: u8): String {
        if (stage == STAGE_EGG) {
            string::utf8(b"Egg")
        } else if (stage == STAGE_BABY) {
            string::utf8(b"Baby")
        } else if (stage == STAGE_ADULT) {
            string::utf8(b"Adult")
        } else {
            string::utf8(b"Elder")
        }
    }

    #[view]
    public fun can_pet_evolve(owner: address, pet_name: String): bool acquires PetStore {
        if (!exists<PetStore>(owner)) {
            return false
        };
        
        let pet_store = borrow_global<PetStore>(owner);
        let pet_index = find_pet_index(&pet_store.pets, &pet_name);
        let pet = vector::borrow(&pet_store.pets, pet_index);
        let current_time = timestamp::now_seconds();
        
        if (pet.status != STATUS_ALIVE) {
            return false
        };
        
        if (pet.stage == STAGE_EGG && current_time >= pet.birth_time + EVOLUTION_TIME) {
            true
        } else if (pet.stage == STAGE_BABY && pet.evolution_points >= 100) {
            true
        } else if (pet.stage == STAGE_ADULT && pet.evolution_points >= 500 && pet.happiness >= 80) {
            true
        } else {
            false
        }
    }
}