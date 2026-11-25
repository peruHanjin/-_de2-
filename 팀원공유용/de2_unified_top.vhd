library ieee;
use ieee.std_logic_1164.all;

-- Master Top-Level Entity: de2_unified_top (SW(4)='0' -> Project 1, SW(4)='1' -> Project 2)
entity de2_unified_top is
    port (
        CLOCK_50                                        : in    std_logic;
        SW                                              : in    std_logic_vector(17 downto 0);
        KEY                                             : in    std_logic_vector(3 downto 0);
        HEX0, HEX1, HEX2, HEX3, HEX4, HEX5, HEX6, HEX7  : out   std_logic_vector(6 downto 0);
        LEDR                                            : out   std_logic_vector(17 downto 0);
        LEDG                                            : out   std_logic_vector(7 downto 0);
        VGA_CLK, VGA_HS, VGA_VS, VGA_BLANK, VGA_SYNC    : out   std_logic;
        VGA_R, VGA_G, VGA_B                             : out   std_logic_vector(9 downto 0)
    );
end entity de2_unified_top;

architecture structural of de2_unified_top is
    signal proj_sel                               : std_logic;
    signal p1_KEY, p2_KEY                         : std_logic_vector(3 downto 0);
    signal p2_SW                                  : std_logic_vector(17 downto 0);
    signal p1_HEX0, p1_HEX1, p1_HEX2, p1_HEX3     : std_logic_vector(6 downto 0);
    signal p1_HEX4, p1_HEX5, p1_HEX6, p1_HEX7     : std_logic_vector(6 downto 0);
    signal p2_HEX0, p2_HEX1, p2_HEX2, p2_HEX3     : std_logic_vector(6 downto 0);
    signal p2_HEX4, p2_HEX5, p2_HEX6, p2_HEX7     : std_logic_vector(6 downto 0);
    signal p1_LEDR, p2_LEDR                       : std_logic_vector(17 downto 0);
    signal p1_LEDG, p2_LEDG                       : std_logic_vector(7 downto 0);
    signal p2_VGA_R, p2_VGA_G, p2_VGA_B           : std_logic_vector(9 downto 0);
begin

    -- SW(4) is unused in both Project 1 (SW(3..0), SW(17..10)) and Project 2 (SW(17..6)),
    -- and leaves SW(5) as a physical buffer gap next to SW(6).
    proj_sel <= SW(4);
    p1_KEY   <= KEY when proj_sel = '0' else "1111";
    p2_KEY   <= KEY when proj_sel = '1' else "1111";
    p2_SW    <= SW  when proj_sel = '1' else (others => '0');

    -- 1. Project 1: Counter + One-Digit Calculator (Active when SW(4) = '0')
    U_PROJECT1 : entity work.project1_top_countercalculator
        port map (
            CLOCK_50 => CLOCK_50, SW => SW, KEY => p1_KEY,
            HEX0 => p1_HEX0, HEX1 => p1_HEX1, HEX2 => p1_HEX2, HEX3 => p1_HEX3,
            HEX4 => p1_HEX4, HEX5 => p1_HEX5, HEX6 => p1_HEX6, HEX7 => p1_HEX7,
            LEDR => p1_LEDR, LEDG => p1_LEDG
        );

    -- 2. Project 2: Crypto Miner Defense Mole Game (Active when SW(4) = '1')
    U_PROJECT2 : entity work.project2_top_mole_game
        port map (
            CLOCK_50 => CLOCK_50, SW => p2_SW, KEY => p2_KEY,
            HEX0 => p2_HEX0, HEX1 => p2_HEX1, HEX2 => p2_HEX2, HEX3 => p2_HEX3,
            HEX4 => p2_HEX4, HEX5 => p2_HEX5, HEX6 => p2_HEX6, HEX7 => p2_HEX7,
            LEDR => p2_LEDR, LEDG => p2_LEDG,
            VGA_CLK => VGA_CLK, VGA_HS => VGA_HS, VGA_VS => VGA_VS,
            VGA_BLANK => VGA_BLANK, VGA_SYNC => VGA_SYNC,
            VGA_R => p2_VGA_R, VGA_G => p2_VGA_G, VGA_B => p2_VGA_B
        );

    -- 3. Global Output Multiplexer (SW(4) = '0' -> Project 1, SW(4) = '1' -> Project 2)
    HEX0  <= p1_HEX0 when proj_sel = '0' else p2_HEX0;
    HEX1  <= p1_HEX1 when proj_sel = '0' else p2_HEX1;
    HEX2  <= p1_HEX2 when proj_sel = '0' else p2_HEX2;
    HEX3  <= p1_HEX3 when proj_sel = '0' else p2_HEX3;
    HEX4  <= p1_HEX4 when proj_sel = '0' else p2_HEX4;
    HEX5  <= p1_HEX5 when proj_sel = '0' else p2_HEX5;
    HEX6  <= p1_HEX6 when proj_sel = '0' else p2_HEX6;
    HEX7  <= p1_HEX7 when proj_sel = '0' else p2_HEX7;
    LEDR  <= p1_LEDR when proj_sel = '0' else p2_LEDR;
    LEDG  <= p1_LEDG when proj_sel = '0' else p2_LEDG;
    VGA_R <= p2_VGA_R when proj_sel = '1' else (others => '0');
    VGA_G <= p2_VGA_G when proj_sel = '1' else (others => '0');
    VGA_B <= p2_VGA_B when proj_sel = '1' else (others => '0');

end architecture structural;
