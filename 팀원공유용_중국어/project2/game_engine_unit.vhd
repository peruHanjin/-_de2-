library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.sprite_reward_pkg.all;

-- ============================================================================
-- Module 4: 3-Round Core Game Engine (60Hz Frame-Driven)
--   1. Player 1 (Human) 8-Direction Tracking toward PS/2 Mouse Cursor
--   2. Player 2 (Mole Boss) Outer-Zone Mole Spawning via DE2 SW(17..6) Clockwise
--      - SW(17)=Zone 0 (Top-Left) .. SW(6)=Zone 11 (Left-Upper)
--      - Max 8 Active Moles on field simultaneously
--      - Consecutive spawns at the exact same zone are blocked
--   3. Mole AI: 8-Direction Autonomous Movement toward Central Coin Pile (240, 240)
--      - Mole speed increases each round (Round 1 -> Round 2 -> Round 3)
--   4. Mining Mechanic: 1-second (60 frames) mining motion -> deducts 1 Coin
--   5. Hammer Attack: Strikes the NEAREST mole within circular range (Radius = 48 px)
--   6. 3-Round Win/Loss Condition (R1/R2=20s, R3=30s, 50 cumulative Coins):
--      - Next Round / Human Wins (game_state = 1) after 3 rounds with Coins > 0
--      - Mole Wins (game_state = 2) immediately if Central Coins reach 0
-- ============================================================================
entity game_engine_unit is
    port (
        CLOCK_50       : in  std_logic;
        reset_n        : in  std_logic;                    -- KEY(3) Active-Low Game Reset
        frame_tick     : in  std_logic;                    -- 60Hz frame pulse from VGA
        -- Player 1 Inputs (PS/2 Mouse + KEY(0))
        cursor_x       : in  integer range 0 to 479;
        cursor_y       : in  integer range 0 to 479;
        mouse_lclick   : in  std_logic;
        attack_key_n   : in  std_logic;                    -- KEY(0) Hammer Attack Button
        -- Player 2 Inputs (DE2 Switches SW(17 downto 6) Clockwise from Top-Left)
        spawn_sw       : in  std_logic_vector(11 downto 0);
        -- Game State Outputs to Renderer & 7-Segment Display
        player_x       : out integer range 0 to 479;
        player_y       : out integer range 0 to 479;
        attack_anim    : out integer range 0 to 15;
        moles_out      : out mole_array_t;
        coin_count     : out integer range 0 to 50;
        kill_count     : out integer range 0 to 50;
        time_left_sec  : out integer range 0 to 30;
        round_num      : out integer range 1 to 3;
        combo_out      : out integer range 0 to 255;
        intro_sec_out  : out integer range 0 to 10;        -- 10s pre-game rules + 3s countdown
        game_state     : out integer range 0 to 2          -- 0=PLAYING, 1=HUMAN_WIN, 2=MOLE_WIN
    );
end entity game_engine_unit;

architecture behavioral of game_engine_unit is

    -- Map & Combat Constants
    constant CENTER_X         : integer := 240;     -- Central Coin Pile X
    constant CENTER_Y         : integer := 240;     -- Central Coin Pile Y
    constant ATTACK_RADIUS_SQ : integer := 48 * 48; -- Hammer Range R = 48 px (R^2 = 2304)
    constant MINE_DISTANCE    : integer := 26;      -- Distance to Coin Pile to start mining

    -- 12 Outer Spawn Coordinates (Placed outside the central 140..340 No-Spawn Square)
    type coord_table_t is array (0 to 11) of integer range 0 to 479;
    constant SPAWN_X_LUT : coord_table_t := (
        60,  180, 300, 420,  -- Top Edge:    Zones 0, 1, 2, 3
        430, 430,            -- Right Edge:  Zones 4, 5
        420, 300, 180, 60,   -- Bottom Edge: Zones 6, 7, 8, 9
        50,  50              -- Left Edge:   Zones 10, 11
    );
    constant SPAWN_Y_LUT : coord_table_t := (
        50,  50,  50,  50,   -- Top Edge
        180, 300,            -- Right Edge
        430, 430, 430, 430,  -- Bottom Edge
        300, 180             -- Left Edge
    );

    -- Game Status Registers
    signal px              : integer range 0 to 479 := 240;
    signal py              : integer range 0 to 479 := 320;
    signal atk_timer       : integer range 0 to 15  := 0;
    signal stun_timer      : integer range 0 to 30  := 0;  -- 0.5s (30 frames) freeze on whiff attack
    signal combo_cnt       : integer range 0 to 255 := 0;  -- Consecutive kills (3/6/9 unlock stages)
    signal hit_step        : integer range 0 to 2   := 0;  -- 3-hit smash counter at 9+ combo
    signal moles           : mole_array_t;
    signal coins           : integer range 0 to 50  := 50; -- Initial 50 Crypto Coins (Cumulative)
    signal kills           : integer range 0 to 50  := 0;  -- Target: 50 Mole Kills per Round
    signal sec_left        : integer range 0 to 30  := 20; -- Round Time: R1/R2=20s, R3=30s
    signal cur_round       : integer range 1 to 3   := 1;  -- Total 3 Rounds (1..3)
    signal intro_sec       : integer range 0 to 10  := 10; -- 10s Rule Screen -> 3s Countdown
    signal frame_cnt_1s    : integer range 0 to 59  := 0;
    signal mole_step_div   : std_logic := '0';
    signal rand_cnt        : integer range 0 to 7   := 0;  -- 50MHz 3-bit RNG for Excadrill spawn rate
    signal state           : integer range 0 to 2   := 0;

    -- Input Edge Detection & Spawn Zone Tracking
    signal atk_prev        : std_logic := '0';
    signal spawn_sw_prev   : std_logic_vector(11 downto 0) := (others => '0');
    signal last_spawn_zone : integer range -1 to 11 := -1; -- Blocks consecutive same-zone spawn

begin

    -- Connect internal registers to entity outputs
    player_x      <= px;
    player_y      <= py;
    attack_anim   <= atk_timer;
    moles_out     <= moles;
    coin_count    <= coins;
    kill_count    <= kills;
    time_left_sec <= sec_left;
    round_num     <= cur_round;
    combo_out     <= combo_cnt;
    intro_sec_out <= intro_sec;
    game_state    <= state;

    process(CLOCK_50, reset_n)
        variable attack_req     : std_logic;
        variable closest_idx    : integer range -1 to MAX_MOLES - 1;
        variable closest_dist2  : integer;
        variable dx, dy         : integer;
        variable dist2          : integer;
        variable next_px        : integer;
        variable next_py        : integer;
        variable spawn_req      : std_logic;
        variable spawn_zone_var : integer range 0 to 11;
        variable mined_coins    : integer range 0 to MAX_MOLES;
        variable step_px        : integer range 0 to 2;
        variable spawn_is_spec  : std_logic;
        variable base_hp        : integer range 1 to 3;
        variable atk_dmg        : integer range 1 to 3;
        variable player_spd     : integer range 2 to 3;
    begin
        if reset_n = '0' then
            px              <= 240;
            py              <= 320;
            atk_timer       <= 0;
            stun_timer      <= 0;
            combo_cnt       <= 0;
            hit_step        <= 0;
            coins           <= 50;
            kills           <= 0;
            sec_left        <= 20;
            cur_round       <= 1;
            intro_sec       <= 10;
            frame_cnt_1s    <= 0;
            mole_step_div   <= '0';
            rand_cnt        <= 0;
            state           <= 0;
            spawn_sw_prev   <= (others => '0');
            last_spawn_zone <= -1;

            -- Clear all 8 Mole Slots
            for i in 0 to MAX_MOLES - 1 loop
                moles(i).active     <= '0';
                moles(i).x          <= 60;
                moles(i).y          <= 50;
                moles(i).kind       <= '0';
                moles(i).hp         <= 0;
                moles(i).mining     <= '0';
                moles(i).mine_timer <= 0;
            end loop;

        elsif rising_edge(CLOCK_50) then
            -- Free-running 3-bit RNG counter (0..7) at 50MHz
            if rand_cnt = 7 then
                rand_cnt <= 0;
            else
                rand_cnt <= rand_cnt + 1;
            end if;

            -- ================================================================
            -- 1. Player 1 Hammer Attack: Hit Nearest Mole or Stun 0.5s on Whiff
            -- ================================================================
            attack_req := (not attack_key_n) or mouse_lclick;

            if state = 0 and intro_sec = 0 and attack_req = '1' and atk_prev = '0' and
               atk_timer = 0 and stun_timer = 0 then
                atk_timer     <= 12; -- Show hammer swing animation for 12 frames (0.2s)
                closest_idx   := -1;
                closest_dist2 := ATTACK_RADIUS_SQ + 1;

                -- Compare squared distance (dx^2 + dy^2) for all active moles
                for i in 0 to MAX_MOLES - 1 loop
                    if moles(i).active = '1' then
                        dx    := moles(i).x - px;
                        dy    := moles(i).y - py;
                        dist2 := (dx * dx) + (dy * dy);

                        -- Check if inside attack circle (R=48) and closer than previous best
                        if dist2 <= ATTACK_RADIUS_SQ and dist2 < closest_dist2 then
                            closest_dist2 := dist2;
                            closest_idx   := i;
                        end if;
                    end if;
                end loop;

                -- Apply combo damage (LV3: 4/8 chance for 3 dmg, no knockback), or stun 0.5s + -1 stage on whiff
                if closest_idx /= -1 then
                    if combo_cnt >= 9 then
                        if rand_cnt < 4 then
                            atk_dmg := 3;
                        else
                            atk_dmg := 2;
                        end if;
                    elsif combo_cnt >= 3 then
                        atk_dmg := 2;
                    else
                        atk_dmg := 1;
                    end if;

                    if moles(closest_idx).hp > atk_dmg then
                        moles(closest_idx).hp <= moles(closest_idx).hp - atk_dmg;
                    else
                        moles(closest_idx).active     <= '0';
                        moles(closest_idx).hp         <= 0;
                        moles(closest_idx).mining     <= '0';
                        moles(closest_idx).mine_timer <= 0;
                        if kills < 50 then
                            kills <= kills + 1;
                        end if;
                        if combo_cnt < 255 then
                            combo_cnt <= combo_cnt + 1;
                        end if;
                    end if;
                else
                    stun_timer <= 30; -- Missed attack -> 0.5s movement/attack freeze
                    -- Drop combo by 1 stage (LV3->LV2(6), LV2->LV1(3), LV1->LV0(0))
                    hit_step   <= 0;
                    if combo_cnt >= 9 then
                        combo_cnt <= 6;
                    elsif combo_cnt >= 6 then
                        combo_cnt <= 3;
                    else
                        combo_cnt <= 0;
                    end if;
                end if;
            end if;
            atk_prev <= attack_req;

            -- ================================================================
            -- 2. 60Hz Frame Tick Update (Timer, Movement, Spawning, Mining)
            -- ================================================================
            if frame_tick = '1' then
                spawn_sw_prev <= spawn_sw;

                if atk_timer > 0 then
                    atk_timer <= atk_timer - 1;
                end if;
                if stun_timer > 0 then
                    stun_timer <= stun_timer - 1;
                end if;

                if state = 0 then
                    -- Pre-Game 10s Rule Explanation & 3s Countdown
                    if intro_sec > 0 then
                        if frame_cnt_1s = 59 then
                            frame_cnt_1s <= 0;
                            intro_sec    <= intro_sec - 1;
                        else
                            frame_cnt_1s <= frame_cnt_1s + 1;
                        end if;
                    -- Check Win / Loss / Round Transition Conditions (3 Rounds x 30s)
                    elsif coins = 0 then
                        state <= 2; -- Player 2 (Mole Boss) Wins!
                    elsif kills >= 50 or sec_left = 0 then
                        if cur_round < 3 then
                            -- Advance to Next Round (Coins & Combo remain cumulative; R2=20s, R3=30s)
                            cur_round       <= cur_round + 1;
                            if cur_round = 1 then
                                sec_left <= 20;
                            else
                                sec_left <= 30;
                            end if;
                            kills           <= 0;
                            frame_cnt_1s    <= 0;
                            stun_timer      <= 0;
                            last_spawn_zone <= -1;
                            for i in 0 to MAX_MOLES - 1 loop
                                moles(i).active     <= '0';
                                moles(i).hp         <= 0;
                                moles(i).mining     <= '0';
                                moles(i).mine_timer <= 0;
                            end loop;
                        else
                            state <= 1; -- Survived all 3 Rounds -> Player 1 (Human) Wins!
                        end if;
                    else
                        -- ----------------------------------------------------
                        -- A. 1-Second Round Countdown Timer (60 frames = 1 sec)
                        -- ----------------------------------------------------
                        if frame_cnt_1s = 59 then
                            frame_cnt_1s <= 0;
                            if sec_left > 0 then
                                sec_left <= sec_left - 1;
                            end if;
                        else
                            frame_cnt_1s <= frame_cnt_1s + 1;
                        end if;

                        -- ----------------------------------------------------
                        -- B. Player 1 (Human) 8-Direction Movement (Frozen if stunned)
                        --    Move speed: 2 px/f (0..5 combo) -> 3 px/f (6+ combo)
                        -- ----------------------------------------------------
                        if stun_timer = 0 then
                            if combo_cnt >= 6 then
                                player_spd := 3;
                            else
                                player_spd := 2;
                            end if;

                            next_px := px;
                            next_py := py;

                            -- Follow PS/2 Mouse Crosshair in 8 Directions
                            if cursor_x > px + player_spd then
                                next_px := px + player_spd;
                            elsif cursor_x < px - player_spd then
                                next_px := px - player_spd;
                            end if;

                            if cursor_y > py + player_spd then
                                next_py := py + player_spd;
                            elsif cursor_y < py - player_spd then
                                next_py := py - player_spd;
                            end if;

                            -- Keep Player 1 inside 480x480 map boundaries
                            if next_px < 16 then
                                px <= 16;
                            elsif next_px > 463 then
                                px <= 463;
                            else
                                px <= next_px;
                            end if;

                            if next_py < 16 then
                                py <= 16;
                            elsif next_py > 463 then
                                py <= 463;
                            else
                                py <= next_py;
                            end if;
                        end if;

                        -- ----------------------------------------------------
                        -- C. Spawn New Mole via SW(17..6) Clockwise (Max 8 Moles)
                        --    - SW(17)=Zone 0 (Top-Left) .. SW(6)=Zone 11 (Left-Upper)
                        --    - Rising edge (0 -> 1) sampled at 60Hz (natural debounce)
                        --    - Block consecutive spawns in the same zone
                        --    - Excadrill probability: R1=1/8, R2=2/8, R3=4/8
                        --    - HP: Diglett = cur_round (1/2/3), Excadrill = 2x (2/4/6)
                        -- ----------------------------------------------------
                        spawn_req      := '0';
                        spawn_zone_var := 0;
                        for z in 0 to 11 loop
                            if spawn_sw(11 - z) = '1' and spawn_sw_prev(11 - z) = '0' then
                                spawn_req      := '1';
                                spawn_zone_var := z;
                                exit;
                            end if;
                        end loop;

                        if spawn_req = '1' then
                            if spawn_zone_var /= last_spawn_zone then
                                if cur_round = 1 then
                                    base_hp := 1;
                                    if rand_cnt = 0 then spawn_is_spec := '1'; else spawn_is_spec := '0'; end if;
                                elsif cur_round = 2 then
                                    base_hp := 2;
                                    if rand_cnt < 2 then spawn_is_spec := '1'; else spawn_is_spec := '0'; end if;
                                else
                                    base_hp := 3;
                                    if rand_cnt < 4 then spawn_is_spec := '1'; else spawn_is_spec := '0'; end if;
                                end if;

                                for i in 0 to MAX_MOLES - 1 loop
                                    if moles(i).active = '0' then
                                        moles(i).active     <= '1';
                                        moles(i).x          <= SPAWN_X_LUT(spawn_zone_var);
                                        moles(i).y          <= SPAWN_Y_LUT(spawn_zone_var);
                                        moles(i).kind       <= spawn_is_spec;
                                        if spawn_is_spec = '1' then
                                            moles(i).hp <= base_hp * 2;
                                        else
                                            moles(i).hp <= base_hp;
                                        end if;
                                        moles(i).mining     <= '0';
                                        moles(i).mine_timer <= 0;
                                        last_spawn_zone     <= spawn_zone_var;
                                        exit; -- Spawn only 1 mole per switch flip
                                    end if;
                                end loop;
                            end if;
                        end if;

                        -- ----------------------------------------------------
                        -- D. Mole 8-Direction AI Movement & 1-Second Mining
                        --    Speed increases each round (Round 1 -> 2 -> 3)
                        -- ----------------------------------------------------
                        mole_step_div <= not mole_step_div;
                        mined_coins   := 0;

                        for i in 0 to MAX_MOLES - 1 loop
                            if moles(i).active = '1' then
                                -- Check if mole has reached the Central Coin Pile (240, 240)
                                if abs(moles(i).x - CENTER_X) <= MINE_DISTANCE and
                                   abs(moles(i).y - CENTER_Y) <= MINE_DISTANCE then
                                    moles(i).mining <= '1';

                                    -- 60 frames at 60Hz = 1.0 second mining motion
                                    if moles(i).mine_timer = 59 then
                                        moles(i).mine_timer <= 0;
                                        mined_coins         := mined_coins + 1;
                                    else
                                        moles(i).mine_timer <= moles(i).mine_timer + 1;
                                    end if;
                                else
                                    -- Walk 8-directionally toward Central Coin Pile
                                    moles(i).mining <= '0';

                                    -- Round-based speed scaling:
                                    --   R1: Diglett = 0.5 px/f, Excadrill = 1.0 px/f
                                    --   R2: Diglett = 1.0 px/f, Excadrill = 1.5 px/f
                                    --   R3: Diglett = 1.5 px/f, Excadrill = 2.0 px/f
                                    if cur_round = 1 then
                                        if moles(i).kind = '1' then
                                            step_px := 1;
                                        elsif mole_step_div = '1' then
                                            step_px := 1;
                                        else
                                            step_px := 0;
                                        end if;
                                    elsif cur_round = 2 then
                                        if moles(i).kind = '1' and mole_step_div = '1' then
                                            step_px := 2;
                                        else
                                            step_px := 1;
                                        end if;
                                    else
                                        if moles(i).kind = '1' then
                                            step_px := 2;
                                        elsif mole_step_div = '1' then
                                            step_px := 2;
                                        else
                                            step_px := 1;
                                        end if;
                                    end if;

                                    if step_px > 0 then
                                        if moles(i).x < CENTER_X - 1 then
                                            moles(i).x <= moles(i).x + step_px;
                                        elsif moles(i).x > CENTER_X + 1 then
                                            moles(i).x <= moles(i).x - step_px;
                                        end if;

                                        if moles(i).y < CENTER_Y - 1 then
                                            moles(i).y <= moles(i).y + step_px;
                                        elsif moles(i).y > CENTER_Y + 1 then
                                            moles(i).y <= moles(i).y - step_px;
                                        end if;
                                    end if;
                                end if;
                            end if;
                        end loop;

                        -- Deduct mined coins from central pile
                        if mined_coins > 0 then
                            if coins > mined_coins then
                                coins <= coins - mined_coins;
                            else
                                coins <= 0;
                            end if;
                        end if;

                    end if;
                end if;
            end if;
        end if;
    end process;

end architecture behavioral;
