library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Top-Level Entity: Counter + One-Digit Calculator (Single-File Unified Version)
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

architecture behavioral of project1_top_countercalculator is

    -- Common 7-Segment Decoder Function (Active-Low: '0' = ON, '1' = OFF)
    function seg7(val : integer) return std_logic_vector is
    begin
        case val is
            when 0      => return "1000000"; -- 0
            when 1      => return "1111001"; -- 1
            when 2      => return "0100100"; -- 2
            when 3      => return "0110000"; -- 3
            when 4      => return "0011001"; -- 4
            when 5      => return "0010010"; -- 5
            when 6      => return "0000010"; -- 6
            when 7      => return "1111000"; -- 7
            when 8      => return "0000000"; -- 8
            when 9      => return "0010000"; -- 9
            when 10     => return "0001000"; -- A
            when 11     => return "0000011"; -- b
            when 12     => return "1000110"; -- C
            when 13     => return "0100001"; -- d
            when 14     => return "0000110"; -- E
            when 15     => return "0001110"; -- F
            when 16     => return "1111111"; -- Blank
            when 17     => return "0111111"; -- '-'
            when 18     => return "0000110"; -- 'E'
            when 19     => return "0101111"; -- 'r'
            when 20     => return "1100001"; -- 'J'
            when 21     => return "0001100"; -- 'P'
            when others => return "1111111"; -- Default: Blank
        end case;
    end function;

    -- Counter Unit Internal Signals
    signal count_val            : integer range -999 to 9999 := 0;
    signal key_sync0, key_sync1 : std_logic_vector(3 downto 0) := (others => '1');
    signal blink_cnt            : unsigned(24 downto 0) := (others => '0');
    signal counter_enable       : std_logic;

    -- Output Multiplexer Signals
    signal cnt_HEX0,  cnt_HEX1,  cnt_HEX2,  cnt_HEX3  : std_logic_vector(6 downto 0);
    signal cnt_HEX4,  cnt_HEX5,  cnt_HEX6,  cnt_HEX7  : std_logic_vector(6 downto 0);
    signal calc_HEX0, calc_HEX1, calc_HEX2, calc_HEX3 : std_logic_vector(6 downto 0);
    signal calc_HEX4, calc_HEX5, calc_HEX6, calc_HEX7 : std_logic_vector(6 downto 0);
    signal cnt_LEDR,  calc_LEDR                       : std_logic_vector(17 downto 0);
    signal cnt_LEDG,  calc_LEDG                       : std_logic_vector(7 downto 0);

begin

    counter_enable <= not SW(0);

    -- =========================================================================
    -- 1. Counter Sequential Process (Falling-Edge Button Detection)
    -- =========================================================================
    process(CLOCK_50)
        variable step, mult : integer;
    begin
        if rising_edge(CLOCK_50) then
            blink_cnt <= blink_cnt + 1;
            key_sync0 <= KEY;
            key_sync1 <= key_sync0;

            if counter_enable = '1' then
                if SW(1) = '0' then mult := 1; else mult := 5; end if;

                if key_sync1(0) = '1' and key_sync0(0) = '0' then
                    count_val <= 0; -- KEY(0): Reset
                else
                    step := 0;
                    if    key_sync1(3) = '1' and key_sync0(3) = '0' then step :=  1 * mult; -- KEY(3): +1 / +5
                    elsif key_sync1(2) = '1' and key_sync0(2) = '0' then step :=  2 * mult; -- KEY(2): +2 / +10
                    elsif key_sync1(1) = '1' and key_sync0(1) = '0' then step := -1 * mult; -- KEY(1): -1 / -5
                    end if;

                    if    count_val + step > 9999 then count_val <= 9999;
                    elsif count_val + step < -999 then count_val <= -999;
                    else  count_val <= count_val + step;
                    end if;
                end if;
            end if;
        end if;
    end process;

    -- =========================================================================
    -- 2. Counter Display Combinational Process
    -- =========================================================================
    process(count_val, blink_cnt)
        variable is_neg  : boolean;
        variable abs_val : integer range 0 to 9999;
    begin
        cnt_HEX7 <= seg7(16); cnt_HEX6 <= seg7(16); cnt_HEX5 <= seg7(16); cnt_HEX4 <= seg7(16);
        cnt_HEX3 <= seg7(16); cnt_HEX2 <= seg7(16); cnt_HEX1 <= seg7(16); cnt_HEX0 <= seg7(16);
        cnt_LEDR <= (others => '0');
        cnt_LEDG <= (others => '0');

        is_neg  := (count_val < 0);
        abs_val := abs(count_val);

        -- [Bonus] Display counter magnitude & sign on Red LEDs
        cnt_LEDR(13 downto 0) <= std_logic_vector(to_unsigned(abs_val, 14));
        if is_neg then cnt_LEDR(17) <= '1'; end if;

        -- [Bonus] Jackpot effect when counter reaches 777
        if count_val = 777 then
            cnt_LEDG <= (others => blink_cnt(23));
            if blink_cnt(23) = '1' then
                cnt_LEDR <= (others => '1');
                cnt_HEX7 <= seg7(20); cnt_HEX6 <= seg7(21); cnt_HEX5 <= seg7(7); cnt_HEX4 <= seg7(7); -- "JP77"
            end if;
        end if;

        -- 4-Digit Decimal Display on HEX3..HEX0
        cnt_HEX0 <= seg7(abs_val mod 10);
        if abs_val >= 10      then cnt_HEX1 <= seg7((abs_val / 10) mod 10);   end if;
        if abs_val >= 100     then cnt_HEX2 <= seg7((abs_val / 100) mod 10);  end if;
        if is_neg             then cnt_HEX3 <= seg7(17);
        elsif abs_val >= 1000 then cnt_HEX3 <= seg7((abs_val / 1000) mod 10); end if;
    end process;

    -- =========================================================================
    -- 3. One-Digit Calculator Combinational Process (+, -, *, /, Dec/Hex, Div-by-0)
    -- =========================================================================
    process(SW)
        variable num_a, num_b, calc_remainder : integer range 0 to 15;
        variable calc_result                  : integer range -15 to 225;
        variable abs_val                      : integer range 0 to 225;
        variable base                         : integer;
        variable div_zero, is_neg             : boolean;
    begin
        calc_HEX7 <= seg7(16); calc_HEX6 <= seg7(16); calc_HEX5 <= seg7(16); calc_HEX4 <= seg7(16);
        calc_HEX3 <= seg7(16); calc_HEX2 <= seg7(16); calc_HEX1 <= seg7(16); calc_HEX0 <= seg7(16);
        calc_LEDR <= (others => '0');
        calc_LEDG <= (others => '0');

        -- Clamp inputs to one-digit decimal (0~9)
        num_a := to_integer(unsigned(SW(17 downto 14)));
        num_b := to_integer(unsigned(SW(13 downto 10)));
        if num_a > 9 then num_a := 9; end if;
        if num_b > 9 then num_b := 9; end if;

        if SW(3) = '1' then base := 16; else base := 10; end if;

        -- Display Operand A on HEX6 and Operand B on HEX4
        calc_HEX6 <= seg7(num_a);
        calc_HEX4 <= seg7(num_b);

        div_zero       := false;
        calc_result    := 0;
        calc_remainder := 0;

        case SW(2 downto 1) is
            when "00"   => calc_result := num_a + num_b;
            when "01"   => calc_result := num_a - num_b;
            when "10"   => calc_result := num_a * num_b;
            when "11"   =>
                if num_b = 0 then div_zero := true;
                else calc_result := num_a / num_b; calc_remainder := num_a mod num_b;
                end if;
            when others => null;
        end case;

        if div_zero then
            -- Exception Handling: Division by 0 -> Display "Err"
            calc_HEX2 <= seg7(18); calc_HEX1 <= seg7(19); calc_HEX0 <= seg7(19);
            calc_LEDR <= (others => '1');
        elsif SW(2 downto 1) = "11" then
            -- [Bonus] Division Quotient on HEX2 & Remainder ('r' + rem) on HEX1..HEX0
            calc_HEX2 <= seg7(calc_result); calc_HEX1 <= seg7(19); calc_HEX0 <= seg7(calc_remainder);
            calc_LEDR(3 downto 0) <= std_logic_vector(to_unsigned(calc_result, 4));
            calc_LEDG(3 downto 0) <= std_logic_vector(to_unsigned(calc_remainder, 4));
        else
            -- Normal Arithmetic Result (+, -, *) in Decimal or Hexadecimal
            is_neg  := (calc_result < 0);
            abs_val := abs(calc_result);

            calc_HEX0 <= seg7(abs_val mod base);
            if abs_val >= base then calc_HEX1 <= seg7((abs_val / base) mod base);
            elsif is_neg       then calc_HEX1 <= seg7(17);
            end if;

            calc_LEDR(7 downto 0) <= std_logic_vector(to_unsigned(abs_val, 8));
        end if;
    end process;

    -- =========================================================================
    -- 4. Output Multiplexer (SW(0) = '0' -> Counter, SW(0) = '1' -> Calculator)
    -- =========================================================================
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

end architecture behavioral;
