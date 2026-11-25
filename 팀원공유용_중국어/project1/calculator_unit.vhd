library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.seg7_pkg.all;

-- Module 2: One-Digit Calculator Unit (+, -, *, /, Dec/Hex, Div-by-0 Exception)
entity calculator_unit is
    port (
        op_a_sw  : in  std_logic_vector(3 downto 0); -- SW(17 downto 14): Operand A
        op_b_sw  : in  std_logic_vector(3 downto 0); -- SW(13 downto 10): Operand B
        op_sel   : in  std_logic_vector(1 downto 0); -- SW(2 downto 1)  : '00'=+, '01'=-, '10'=*, '11'=/
        base_sel : in  std_logic;                    -- SW(3)           : '0'=Decimal, '1'=Hexadecimal
        HEX0, HEX1, HEX2, HEX3, HEX4, HEX5, HEX6, HEX7 : out std_logic_vector(6 downto 0);
        LEDR     : out std_logic_vector(17 downto 0);
        LEDG     : out std_logic_vector(7 downto 0)
    );
end entity calculator_unit;

architecture behavioral of calculator_unit is
begin

    process(op_a_sw, op_b_sw, op_sel, base_sel)
        variable num_a, num_b, calc_remainder : integer range 0 to 15;
        variable calc_result               : integer range -15 to 225;
        variable abs_val                : integer range 0 to 225;
        variable base                   : integer;
        variable div_zero, is_neg       : boolean;
    begin
        HEX7 <= seg7(16); HEX6 <= seg7(16); HEX5 <= seg7(16); HEX4 <= seg7(16);
        HEX3 <= seg7(16); HEX2 <= seg7(16); HEX1 <= seg7(16); HEX0 <= seg7(16);
        LEDR <= (others => '0');
        LEDG <= (others => '0');

        -- Clamp inputs to one-digit decimal (0~9)
        num_a := to_integer(unsigned(op_a_sw));
        num_b := to_integer(unsigned(op_b_sw));
        if num_a > 9 then num_a := 9; end if;
        if num_b > 9 then num_b := 9; end if;
        
        -- base를 결정
        if base_sel = '1' then base := 16; else base := 10; end if;

        -- Display Operand A on HEX6 and Operand B on HEX4
        HEX6 <= seg7(num_a);
        HEX4 <= seg7(num_b);

        div_zero := false;
        calc_result := 0;
        calc_remainder := 0;
        
        -- calc_result, div_zero, calc_remainder를 결정
        case op_sel is   
            when "00"   => calc_result := num_a + num_b;
            when "01"   => calc_result := num_a - num_b;
            when "10"   => calc_result := num_a * num_b;
            when "11"   =>
                if num_b = 0 then div_zero := true;
                else calc_result := num_a / num_b; calc_remainder := num_a mod num_b;
                end if;
            when others => null;
        end case;
        -- 나눗셈에서도 16진수 고려x(최대 9, 최소 1이다)
        if div_zero then
            -- Exception Handling: Division by 0 -> Display "Err"
            HEX2 <= seg7(18); HEX1 <= seg7(19); HEX0 <= seg7(19);
            LEDR <= (others => '1');
        elsif op_sel = "11" then
            -- [Bonus] Division Quotient on HEX2 & Remainder ('r' + rem) on HEX1..HEX0
            HEX2 <= seg7(calc_result); HEX1 <= seg7(19); HEX0 <= seg7(calc_remainder);
            LEDR(3 downto 0) <= std_logic_vector(to_unsigned(calc_result, 4));
            LEDG(3 downto 0) <= std_logic_vector(to_unsigned(calc_remainder, 4));
        else
            -- Normal Arithmetic Result (+, -, *) in Decimal or Hexadecimal
            -- is_neg, abs_val를 결정
            is_neg  := (calc_result < 0);
            abs_val := abs(calc_result);

            HEX0 <= seg7(abs_val mod base);
            -- 2번째 자리 결정(덧셈과 곱셈은 여기서 끝난다. 덧셈최대 18, 곱셈최대 81, 16진수 변환은 덧셈, 곱셈에서만 고려한다.)
            if abs_val >= base then HEX1 <= seg7((abs_val / base) mod base);
            -- 한자리 음수 - 붙이기(음수의 최대가 -9이다 16진수변환 고려x)
            elsif is_neg       then HEX1 <= seg7(17);
            end if;

            LEDR(7 downto 0) <= std_logic_vector(to_unsigned(abs_val, 8));
        end if;
    end process;

end architecture behavioral;
