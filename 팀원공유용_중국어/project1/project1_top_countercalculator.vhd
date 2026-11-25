library ieee;
use ieee.std_logic_1164.all;

-- Top-Level Entity: Counter + One-Digit Calculator (Hierarchical Design)
entity project1_top_countercalculator is
    port (
        CLOCK_50 : in  std_logic;
        SW       : in  std_logic_vector(17 downto 0);
        KEY      : in  std_logic_vector(3 downto 0);
        HEX0, HEX1, HEX2, HEX3, HEX4, HEX5, HEX6, HEX7 : out std_logic_vector(6 downto 0);
        LEDR     : out std_logic_vector(17 downto 0);
        LEDG     : out std_logic_vector(7 downto 0)
    );
end entity project1_top_countercalculator;

architecture structural of project1_top_countercalculator is
    signal cnt_HEX0,  cnt_HEX1,  cnt_HEX2,  cnt_HEX3  : std_logic_vector(6 downto 0);
    signal cnt_HEX4,  cnt_HEX5,  cnt_HEX6,  cnt_HEX7  : std_logic_vector(6 downto 0);
    signal calc_HEX0, calc_HEX1, calc_HEX2, calc_HEX3 : std_logic_vector(6 downto 0);
    signal calc_HEX4, calc_HEX5, calc_HEX6, calc_HEX7 : std_logic_vector(6 downto 0);
    signal cnt_LEDR,  calc_LEDR                       : std_logic_vector(17 downto 0);
    signal cnt_LEDG,  calc_LEDG                       : std_logic_vector(7 downto 0);
    signal counter_enable                             : std_logic;
begin

    counter_enable <= not SW(0);

    -- 1. Counter Module Instantiation (Active when SW(0) = '0')
    U_COUNTER : entity work.counter_unit
        port map (
            CLOCK_50 => CLOCK_50, enable => counter_enable, step_mode => SW(1), KEY => KEY,
            HEX0 => cnt_HEX0, HEX1 => cnt_HEX1, HEX2 => cnt_HEX2, HEX3 => cnt_HEX3,
            HEX4 => cnt_HEX4, HEX5 => cnt_HEX5, HEX6 => cnt_HEX6, HEX7 => cnt_HEX7,
            LEDR => cnt_LEDR, LEDG => cnt_LEDG
        );

    -- 2. Calculator Module Instantiation (Active when SW(0) = '1')
    U_CALCULATOR : entity work.calculator_unit
        port map (
            op_a_sw => SW(17 downto 14), op_b_sw => SW(13 downto 10),
            op_sel  => SW(2 downto 1),   base_sel => SW(3),
            HEX0 => calc_HEX0, HEX1 => calc_HEX1, HEX2 => calc_HEX2, HEX3 => calc_HEX3,
            HEX4 => calc_HEX4, HEX5 => calc_HEX5, HEX6 => calc_HEX6, HEX7 => calc_HEX7,
            LEDR => calc_LEDR, LEDG => calc_LEDG
        );

    -- 3. Output Multiplexer (SW(0) = '0' -> Counter, SW(0) = '1' -> Calculator)
    HEX0 <= cnt_HEX0 when SW(0) = '0' else calc_HEX0;
    HEX1 <= cnt_HEX1 when SW(0) = '0' else calc_HEX1;
    HEX2 <= cnt_HEX2 when SW(0) = '0' else calc_HEX2;
    HEX3 <= cnt_HEX3 when SW(0) = '0' else calc_HEX3;
    HEX4 <= cnt_HEX4 when SW(0) = '0' else calc_HEX4;
    HEX5 <= cnt_HEX5 when SW(0) = '0' else calc_HEX5;
    HEX6 <= cnt_HEX6 when SW(0) = '0' else calc_HEX6;
    HEX7 <= cnt_HEX7 when SW(0) = '0' else calc_HEX7;
    LEDR <= cnt_LEDR when SW(0) = '0' else calc_LEDR;
    LEDG <= cnt_LEDG when SW(0) = '0' else calc_LEDG;

end architecture structural;
