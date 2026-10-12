library verilog;
use verilog.vl_types.all;
entity control_core is
    generic(
        CENTER          : integer := 2098;
        CAPTURE_RANGE   : integer := 500;
        START_PERCENT   : integer := 35;
        PULSE_MS        : integer := 100;
        CHECK_MS        : integer := 40;
        ANGLE_MS        : integer := 5;
        POSITION_MS     : integer := 50;
        SWING_TIMEOUT_MS: integer := 15000;
        POSITION_LIMIT_COUNTS: integer := 4080;
        ANGLE_KP        : vl_logic_vector(31 downto 0) := (Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi1, Hi0, Hi1, Hi1, Hi1, Hi0, Hi1, Hi0, Hi1, Hi1, Hi1, Hi0, Hi0, Hi0, Hi1);
        ANGLE_KI        : vl_logic_vector(31 downto 0) := (Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi1, Hi0, Hi1, Hi0, Hi0, Hi0, Hi1, Hi1, Hi1, Hi1);
        ANGLE_KD        : vl_logic_vector(31 downto 0) := (Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi1, Hi1, Hi0, Hi0, Hi1, Hi1, Hi0, Hi0, Hi1, Hi1, Hi0, Hi0, Hi1, Hi1, Hi0);
        POSITION_KP     : vl_logic_vector(31 downto 0) := (Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi1, Hi1, Hi0, Hi0, Hi1, Hi1, Hi0, Hi0, Hi1, Hi1, Hi0, Hi0, Hi1, Hi1, Hi0);
        POSITION_KI     : vl_logic_vector(31 downto 0) := (Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0);
        POSITION_KD     : vl_logic_vector(31 downto 0) := (Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi1, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0)
    );
    port(
        clk             : in     vl_logic;
        rst_n           : in     vl_logic;
        sample_valid    : in     vl_logic;
        sample_ready    : in     vl_logic;
        sample          : in     vl_logic_vector(11 downto 0);
        position        : in     vl_logic_vector(31 downto 0);
        start_cmd       : in     vl_logic;
        stop_cmd        : in     vl_logic;
        permit          : in     vl_logic;
        fault_latched   : in     vl_logic;
        running         : out    vl_logic;
        command_q       : out    vl_logic_vector(31 downto 0);
        state           : out    vl_logic_vector(2 downto 0);
        request_fault   : out    vl_logic_vector(3 downto 0);
        relative_position: out    vl_logic_vector(31 downto 0);
        angle_update    : out    vl_logic;
        position_update : out    vl_logic
    );
    attribute mti_svvh_generic_type : integer;
    attribute mti_svvh_generic_type of CENTER : constant is 2;
    attribute mti_svvh_generic_type of CAPTURE_RANGE : constant is 2;
    attribute mti_svvh_generic_type of START_PERCENT : constant is 2;
    attribute mti_svvh_generic_type of PULSE_MS : constant is 2;
    attribute mti_svvh_generic_type of CHECK_MS : constant is 2;
    attribute mti_svvh_generic_type of ANGLE_MS : constant is 2;
    attribute mti_svvh_generic_type of POSITION_MS : constant is 2;
    attribute mti_svvh_generic_type of SWING_TIMEOUT_MS : constant is 2;
    attribute mti_svvh_generic_type of POSITION_LIMIT_COUNTS : constant is 2;
    attribute mti_svvh_generic_type of ANGLE_KP : constant is 2;
    attribute mti_svvh_generic_type of ANGLE_KI : constant is 2;
    attribute mti_svvh_generic_type of ANGLE_KD : constant is 2;
    attribute mti_svvh_generic_type of POSITION_KP : constant is 2;
    attribute mti_svvh_generic_type of POSITION_KI : constant is 2;
    attribute mti_svvh_generic_type of POSITION_KD : constant is 2;
end control_core;
