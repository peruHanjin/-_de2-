library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.seg7_pkg.all;

-- Module 1: Counter Unit (Synchronous Button Edge Detection + 777 Jackpot)
entity counter_unit is
    port (
        CLOCK_50  : in  std_logic;
        enable    : in  std_logic;                    -- '1' when Counter Mode (SW(0) = '0')
        step_mode : in  std_logic;                    -- SW(1): '0' = +1/+2/-1, '1' = +5/+10/-5
        KEY       : in  std_logic_vector(3 downto 0); -- KEY(3..0) Active-Low Buttons
        HEX0, HEX1, HEX2, HEX3, HEX4, HEX5, HEX6, HEX7 : out std_logic_vector(6 downto 0);
        LEDR      : out std_logic_vector(17 downto 0);
        LEDG      : out std_logic_vector(7 downto 0)
    );
end entity counter_unit;

architecture behavioral of counter_unit is
    signal count_val            : integer range -999 to 9999 := 0;
    signal key_sync0, key_sync1 : std_logic_vector(3 downto 0) := (others => '1');
    signal blink_cnt            : unsigned(24 downto 0) := (others => '0');
begin

    -- 1. Counter Sequential Process (Falling-Edge Button Detection)
    process(CLOCK_50)
        -- step(이번 클럭 증감량)과 mult(배수 1 또는 5)
        variable step, mult : integer;
    begin
        if rising_edge(CLOCK_50) then
            blink_cnt <= blink_cnt + 1;
            -- key_sync0(현재 샘플)
            key_sync0 <= KEY;
            -- key_sync1(1클럭 전 샘플)
            key_sync1 <= key_sync0;

            if enable = '1' then
                if step_mode = '0' then mult := 1; else mult := 5; end if;

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

    -- 2. Counter Display Combinational Process
    process(count_val, blink_cnt)
        variable is_neg  : boolean;
        variable abs_val : integer range 0 to 9999;
    begin
        HEX7 <= seg7(16); HEX6 <= seg7(16); HEX5 <= seg7(16); HEX4 <= seg7(16);
        HEX3 <= seg7(16); HEX2 <= seg7(16); HEX1 <= seg7(16); HEX0 <= seg7(16);
        LEDR <= (others => '0');
        LEDG <= (others => '0');

        is_neg  := (count_val < 0);
        abs_val := abs(count_val);

        -- [Bonus] Display counter magnitude & sign on Red LEDs
        LEDR(13 downto 0) <= std_logic_vector(to_unsigned(abs_val, 14));
        if is_neg then LEDR(17) <= '1'; end if;

        -- [Bonus] Jackpot effect when counter reaches 777
        if count_val = 777 then
            LEDG <= (others => blink_cnt(23));
            -- 위에 프로세스에서 1씩 증가하므로 무조건 2의 23승 클럭마다 뒤집힘
            if blink_cnt(23) = '1' then
                LEDR <= (others => '1');
                HEX7 <= seg7(20); HEX6 <= seg7(21); HEX5 <= seg7(7); HEX4 <= seg7(7); -- "JP77"
            end if;
        end if;

        -- 4-Digit Decimal Display on HEX3..HEX0
        HEX0 <= seg7(abs_val mod 10);
        if abs_val >= 10      then HEX1 <= seg7((abs_val / 10) mod 10);   end if;
        if abs_val >= 100     then HEX2 <= seg7((abs_val / 100) mod 10);  end if;
        if is_neg             then HEX3 <= seg7(17);
        elsif abs_val >= 1000 then HEX3 <= seg7((abs_val / 1000) mod 10); end if;
    end process;

end architecture behavioral;
