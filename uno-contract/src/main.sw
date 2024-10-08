contract;

use std::{
    auth::msg_sender,
    block::timestamp,
    hash::*,
    logging::log,
    vec::Vec,
    storage::storage_vec::*,
};

abi UnoGame {
    #[storage(read, write)]
    fn create_game() -> u64;
    #[storage(read, write)]
    fn start_game(game_id: u64, initial_state_hash: b256);
    #[storage(read, write)]
    fn join_game(game_id: u64);
}

struct Game {
    id: u64,
    is_active: bool,
    current_player_index: u64,
    state_hash: b256,
    last_action_timestamp: u64,
    turn_count: u64,
    direction_clockwise: bool,
    is_started: bool,
}

struct Action {
    player: Address,
    action_hash: b256,
    timestamp: u64,
}


storage {
    game_id_counter: u64 = 0,
    active_games: StorageVec<u64> = StorageVec {},
    games: StorageMap<u64, Game> = StorageMap {},
    game_players: StorageMap<u64, StorageVec<Address>> = StorageMap {},
    game_actions: StorageVec<StorageVec<Action>> = StorageVec {},
}


impl UnoGame for Contract {
    #[storage(read, write)]
    fn create_game() -> u64 {
        let sender = msg_sender().unwrap();
        let creator_address = match sender {
            Identity::Address(addr) => addr,
            _ => revert(0),
        };
        let current_counter = storage.game_id_counter.read();
        storage.game_id_counter.write(current_counter + 1);
        let new_game_id = storage.game_id_counter.read();

        storage.game_players.insert(new_game_id, StorageVec {});

        let players = storage.game_players.get(new_game_id);
        players.push(creator_address);

        let mut combined_hash = b256::zero();
        let mut index = 0;
        while index < players.len() {
            let player_key = players.get(index).unwrap();
            let player = player_key.try_read().unwrap(); 
            let player_hash = keccak256(player);
            combined_hash = keccak256((combined_hash, player_hash));
            index += 1;
        }

        let seed = keccak256((timestamp(), sender, combined_hash));
        let initial_state_hash = keccak256((new_game_id, seed));

        let new_game = Game {
            id: new_game_id,
            is_active: true,
            current_player_index: 0,
            state_hash: initial_state_hash,
            last_action_timestamp: timestamp(),
            turn_count: 0,
            direction_clockwise: true,
            is_started: false,
        };

        storage.games.insert(new_game_id, new_game);
        storage.active_games.push(new_game_id);

        // Emit GameCreated event
        log(GameCreated {
            game_id: new_game_id,
            creator: creator_address,
        });

        new_game_id
    }

    #[storage(read, write)]
    fn start_game(game_id: u64, initial_state_hash: b256) {
        let mut game = storage.games.get(game_id).try_read().unwrap();
        assert(!game.is_started); //"Game already started"
        assert(storage.game_players.get(game_id).len() < 2); //"Not enough players"

        game.is_started = true;
        game.state_hash = initial_state_hash;
        game.last_action_timestamp = timestamp();

        storage.games.insert(game_id, game);

        // Emit GameStarted event
        log(GameStarted {
            game_id: game_id,
            initial_state_hash: initial_state_hash,
        });
    }

    #[storage(read, write)]
    fn join_game(game_id: u64) {
        let sender = msg_sender().unwrap();
        let sender_address = match sender {
            Identity::Address(addr) => addr,
            _ => revert(0),
        };
        
        let mut game = storage.games.get(game_id).try_read().unwrap();
        assert(!game.is_active); //"Game is not active"
        assert(storage.game_players.get(game_id).len() < 10); //"Game is full"
        
        let players_key = storage.game_players.get(game_id);
        let mut players_vec = players_key.try_read().unwrap();
        
        players_vec.push(sender_address);
        
        storage.game_players.insert(game_id, players_vec);

        // Emit PlayerJoined event
        log(PlayerJoined {
            game_id: game_id,
            player: sender_address,
        });
    }
}

// Private/Internal helper functions
//fn hash_players(game_id: u64, players: &StorageVec<Address>, sender: Address) -> b256 {
//    let mut combined_hash = b256::zero();
//    let mut index = 0;
//    while index < players.len() {
//        let player_key = players.get(index).unwrap();
//        let player = player_key.try_read().unwrap(); 
//        let player_hash = keccak256(player);
//        combined_hash = keccak256((combined_hash, player_hash));
//        index += 1;
//    }
//
//    let seed = keccak256((timestamp(), sender, combined_hash));
//    keccak256((game_id, seed))
//}

// Event structse
struct GameCreated {
    game_id: u64,
    creator: Address,
}

struct GameStarted {
    game_id: u64,
    initial_state_hash: b256,
}

struct PlayerJoined {
    game_id: u64,
    player: Address,
}

struct ActionSubmitted {
    game_id: u64,
    player: Address,
    action_hash: b256,
}

struct GameEnded {
    game_id: u64,
}
