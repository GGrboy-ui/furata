library verilog;
use verilog.vl_types.all;
entity encoder_qei is
    generic(
        CLK_HZ          : integer := 50000000;
        VEL_FRAC        : integer := 8;
        VEL_TIMEOUT_CLKS: integer := 50000000
    );
    port(
        clk             : in     vl_logic;
        rst_n           : in     vl_logic;
        enc_a           : in     vl_logic;
        enc_b           : in     vl_logic;
        tick_speed      : in     vl_logic;
        position        : out    vl_logic_vector(31 downto 0);
        vel             : out    vl_logic_vector(31 downto 0);
        delta           : out    vl_logic_vector(31 downto 0)
    );
    attribute mti_svvh_generic_type : integer;
    attribute mti_svvh_generic_type of CLK_HZ : constant is 2;
    attribute mti_svvh_generic_type of VEL_FRAC : constant is 2;
    attribute mti_svvh_generic_type of VEL_TIMEOUT_CLKS : constant is 2;
end encoder_qei;
