library verilog;
use verilog.vl_types.all;
entity pwm_motor is
    generic(
        PWM_MAX         : vl_logic_vector(15 downto 0) := (Hi0, Hi0, Hi0, Hi0, Hi1, Hi0, Hi0, Hi1, Hi1, Hi1, Hi0, Hi0, Hi0, Hi1, Hi0, Hi0);
        SLEW_STEP       : vl_logic_vector(15 downto 0) := (Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi1, Hi0, Hi0);
        DEAD_CYCLES     : vl_logic_vector(15 downto 0) := (Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi1, Hi0, Hi0, Hi0);
        BRAKE_ON_INHIBIT: integer := 1
    );
    port(
        clk             : in     vl_logic;
        rst_n           : in     vl_logic;
        enable          : in     vl_logic;
        brake           : in     vl_logic;
        cmd             : in     vl_logic_vector(15 downto 0);
        pwm             : out    vl_logic;
        in1             : out    vl_logic;
        in2             : out    vl_logic
    );
    attribute mti_svvh_generic_type : integer;
    attribute mti_svvh_generic_type of PWM_MAX : constant is 2;
    attribute mti_svvh_generic_type of SLEW_STEP : constant is 2;
    attribute mti_svvh_generic_type of DEAD_CYCLES : constant is 2;
    attribute mti_svvh_generic_type of BRAKE_ON_INHIBIT : constant is 2;
end pwm_motor;
