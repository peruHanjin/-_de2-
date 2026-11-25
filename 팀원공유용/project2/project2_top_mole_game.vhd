library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.seg7_pkg.all;
use work.sprite_reward_pkg.all;

-- ============================================================================
-- Project 2 Sub-Top Entity: project2_top_mole_game
-- Connects:
--   1. U_VGA_CTRL     (vga_controller)
--   2. U_GAME_ENGINE  (game_engine_unit : Player 1 KEY(3..0), Player 2 SW(17..6))
--   3. U_VGA_RENDERER (vga_renderer_unit)
--   4. On-Board 7-Segment (HEX7..HEX0) and LEDs (LEDR, LEDG)
-- ============================================================================
entity project2_top_mole_game is
    port (
        CLOCK_50  : in    std_logic;
        SW        : in    std_logic_vector(17 downto 0);
        KEY       : in    std_logic_vector(3 downto 0);
        HEX0      : out   std_logic_vector(6 downto 0);
        HEX1      : out   std_logic_vector(6 downto 0);
        HEX2      : out   std_logic_vector(6 downto 0);
        HEX3      : out   std_logic_vector(6 downto 0);
        HEX4      : out   std_logic_vector(6 downto 0);
        HEX5      : out   std_logic_vector(6 downto 0);
        HEX6      : out   std_logic_vector(6 downto 0);
        HEX7      : out   std_logic_vector(6 downto 0);
        LEDR      : out   std_logic_vector(17 downto 0);
        LEDG      : out   std_logic_vector(7 downto 0);
        -- External Peripherals (VGA)
        VGA_CLK   : out   std_logic;
        VGA_HS    : out   std_logic;
        VGA_VS    : out   std_logic;
        VGA_BLANK : out   std_logic;
        VGA_SYNC  : out   std_logic;
        VGA_R     : out   std_logic_vector(9 downto 0);
        VGA_G     : out   std_logic_vector(9 downto 0);
        VGA_B     : out   std_logic_vector(9 downto 0)
    );
end entity project2_top_mole_game;

architecture structural of project2_top_mole_game is

    -- Reset & VGA Timing Signals
    signal reset_n        : std_logic;
    signal video_on       : std_logic;
    signal frame_tick     : std_logic;
    signal pixel_x        : integer range 0 to 799;
    signal pixel_y        : integer range 0 to 524;

    -- Game Engine State Signals
    signal player_x       : integer range 0 to 479;
    signal player_y       : integer range 0 to 479;
    signal attack_anim    : integer range 0 to 15;
    signal moles          : mole_array_t;
    signal coin_count     : integer range 0 to 50;
    signal time_left_sec  : integer range 0 to 30;
    signal round_num      : integer range 1 to 3;
    signal combo_cnt      : integer range 0 to 255;
    signal intro_sec      : integer range 0 to 10;
    signal game_state     : integer range 0 to 2;

begin

    -- SW(4) is Project 2 Mode Enable & Active-Low Reset ('0' = Reset, '1' = Active)
    reset_n <= SW(4);

    -- 1. VGA 640x480 @ 60Hz Timing Generator (Always running so TV/Monitor never loses sync)
    U_VGA_CTRL : entity work.vga_controller
        port map (
            CLOCK_50   => CLOCK_50,
            reset_n    => '1',
            vga_clk    => VGA_CLK,
            hsync      => VGA_HS,
            vsync      => VGA_VS,
            blank_n    => VGA_BLANK,
            sync_n     => VGA_SYNC,
            video_on   => video_on,
            frame_tick => frame_tick,
            pixel_x    => pixel_x,
            pixel_y    => pixel_y
        );

    -- 2. 3-Round Core Game Engine (Player 1 KEY(3..0), Player 2 Spawns via SW(17..6) Clockwise)
    U_GAME_ENGINE : entity work.game_engine_unit
        port map (
            CLOCK_50      => CLOCK_50,
            reset_n       => reset_n,
            frame_tick    => frame_tick,
            move_up_n     => KEY(3),
            move_left_n   => KEY(2),
            move_right_n  => KEY(1),
            attack_key_n  => KEY(0),
            spawn_sw      => SW(17 downto 6),
            player_x      => player_x,
            player_y      => player_y,
            attack_anim   => attack_anim,
            moles_out     => moles,
            coin_count    => coin_count,
            time_left_sec => time_left_sec,
            round_num     => round_num,
            combo_out     => combo_cnt,
            intro_sec_out => intro_sec,
            game_state    => game_state
        );

    -- 5. Real-Time VGA Sprite & Reward Link/Code Renderer
    U_VGA_RENDERER : entity work.vga_renderer_unit
        port map (
            video_on      => video_on,
            pixel_x       => pixel_x,
            pixel_y       => pixel_y,
            cursor_x      => player_x,
            cursor_y      => player_y,
            player_x      => player_x,
            player_y      => player_y,
            attack_anim   => attack_anim,
            moles         => moles,
            coin_count    => coin_count,
            time_left_sec => time_left_sec,
            round_num     => round_num,
            combo_cnt     => combo_cnt,
            intro_sec     => intro_sec,
            game_state    => game_state,
            vga_r         => VGA_R,
            vga_g         => VGA_G,
            vga_b         => VGA_B
        );

    -- 6. On-Board 7-Segment & LED Status Display
    process(coin_count, time_left_sec, round_num, moles, attack_anim)
    begin
        -- HEX7..HEX6: Remaining Crypto Coins (50 down to 00)
        HEX7 <= seg7((coin_count / 10) mod 10);
        HEX6 <= seg7(coin_count mod 10);

        -- HEX5: Blank (OFF)
        HEX5 <= seg7(16);

        -- HEX4: Current Round (1..3)
        HEX4 <= seg7(round_num);

        -- HEX3..HEX2: Blank (OFF)
        HEX3 <= seg7(16);
        HEX2 <= seg7(16);

        -- HEX1..HEX0: Time Remaining (Seconds mod 100)
        HEX1 <= seg7((time_left_sec / 10) mod 10);
        HEX0 <= seg7(time_left_sec mod 10);

        -- LEDR: Only LEDR(15..8) Coin Mining Warning LEDs (Slots 0..7)
        LEDR <= (others => '0');
        for i in 0 to MAX_MOLES - 1 loop
            LEDR(i + 8) <= moles(i).mining;
        end loop;

        -- LEDG: Only LEDG(3..0) Hammer Attack Animation Indicator
        LEDG <= (others => '0');
        if attack_anim > 0 then
            LEDG(3 downto 0) <= "1111";
        end if;
    end process;

end architecture structural;
