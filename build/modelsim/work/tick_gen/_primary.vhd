library verilog;
use verilog.vl_types.all;
entity tick_gen is
    generic(
        CLK_HZ          : integer := 50000000;
        CTRL_HZ         : integer := 1000;
        SPEED_HZ        : integer := 5000;
        LOG_HZ          : integer := 10
    );
    port(
        clk             : in     vl_logic;
        rst_n           : in     vl_logic;
        tick_speed      : out    vl_logic;
        tick_ctrl       : out    vl_logic;
        tick_log        : out    vl_logic
    );
    attribute mti_svvh_generic_type : integer;
    attribute mti_svvh_generic_type of CLK_HZ : constant is 2;
    attribute mti_svvh_generic_type of CTRL_HZ : constant is 2;
    attribute mti_svvh_generic_type of SPEED_HZ : constant is 2;
    attribute mti_svvh_generic_type of LOG_HZ : constant is 2;
end tick_gen;
